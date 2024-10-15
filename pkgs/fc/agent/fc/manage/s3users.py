"""realises pending actions on S3 users based on directory data;
accountig for usage data"""

import argparse
import errno
import json
import sys
from subprocess import CalledProcessError
from typing import Optional

import structlog
from fc.util.directory import connect
from fc.util.logging import init_logging
from fc.util.runners import run

log = structlog.get_logger()


def list_radosgw_users() -> list[str]:
    """List all uids of users known to the local radosgw"""
    return run.json.radosgw_admin("user", "list")


def accounting(location: str, dir_conn):
    """Uploads usage data from Ceph/RadosGW into the Directory"""
    users = list_radosgw_users()

    usage = dict()
    for user in users:
        stats = run.json.radosgw_admin("user", "stats", "--uid", user)
        usage[user] = str(stats["stats"]["total_bytes"])

    dir_conn.store_s3(location, usage)


class RadosgwUserManager:

    def __init__(self, directory_connection, location: str, rg: str):
        self.dir_conn = directory_connection
        self.location = location
        self.rg = rg
        self.processing_errors = False

    def get_local_user_report(self) -> dict[str, dict]:
        """Retrieve details about all locally known radosgw users for reporting to
        directory"""
        user_report = dict()
        for uid in list_radosgw_users():
            user_info = run.json.radosgw_admin("user", "info", "--uid", uid)
            try:
                main_key = user_info["keys"][0]
                key = {
                    "access_key": main_key["access_key"],
                    "secret_key": main_key["secret_key"],
                }
            except IndexError:
                key = {"access_key": None, "secret_key": None}
            if (num_keys := len(user_info["keys"])) > 1:
                log.error(
                    f"radosgw user {uid} has {num_keys}, this is more then expected"
                )
                self.processing_errors = True
            user_report[uid] = dict(
                display_name=user_info["display_name"], **key
            )

        return user_report

    def get_directory_user_report(self) -> dict[str, dict]:
        """Retrieve user data from directory"""
        return self.dir_conn.list_s3_users(
            location=self.location, storage_resource_group_filter=self.rg
        )

    @staticmethod
    def check_user(
        uid: str,
        directory_user: Optional[dict],
        local_user: Optional[dict],
    ) -> Optional[str]:
        """Check whether the local user data corresponds to the data received
        from directory.
        return value: Error message str on mismatch, None when equal"""
        mismatches: list[str] = []
        compare_properties = ("display_name", "access_key")
        missing = False
        if not directory_user:
            mismatches.append(f"- not found in directory users")
            missing = True
        if not local_user:
            mismatches.append(f"- not found in local users")
            missing = True
        for prop in compare_properties:
            # make MyPy happy
            assert directory_user is not None and local_user is not None
            if (not missing) and directory_user[prop] != local_user[prop]:
                mismatches.append(f"- differ in {prop}")

        return (
            f"User data mismatch for {uid}:\n" + "\n\t".join(mismatches)
            if mismatches
            else None
        )

    def sync_users(self):
        local_users = self.get_local_user_report()
        directory_users = self.get_directory_user_report()

        for uid, directory_user_dict in directory_users.items():
            try:
                # TODO: too much indentation, refactor?
                match directory_user_dict["status"]:
                    case "pending":
                        self.ensure_radosgw_user(
                            directory_user_dict, replace=uid in local_users
                        )
                        break
                    case "active":
                        if err := self.check_user(
                            directory_user=directory_user_dict,
                            local_user=local_users.get(uid, None),
                        ):
                            # FIXME: could we provide the error list directly to structlog?
                            log.error(err)
                            self.processing_errors = True
                        break
                    case "pending_deletion":
                        if "soft" in directory_user_dict["deletion"]["stages"]:
                            try:
                                local_user_dict = local_users[uid]
                            except KeyError:
                                log.error(
                                    f"User {uid} not found locally, soft deletion failed."
                                )
                                self.processing_errors = True
                            else:
                                self.purge_user_keys(uid)
                                local_users[uid]["access_key"] = None
                                local_users[uid]["secret_key"] = None
                        if "hard" in directory_user_dict["deletion"]["stages"]:
                            # needs to be idempotent/ still pass when user does not exist anymore
                            self.remove_user()
                            local_users.pop(uid, None)
                        break
            except Exception:
                # individual errors shall not block progress on all other users
                log.exception(
                    f"Encountered an error while handling {uid}, continuing:"
                )
                self.processing_errors = True

        # report_users: report all users present with uid, display_name, access_key
        self.report_to_directory(local_users)

        def report_to_directory(self, users):
            dir_conn.update_s3_users(
                {
                    uid: user_dict.update(
                        {
                            # directory ring0 API wants to have RG and location as explicit values
                            "location": self.location,
                            "storage_resource_group": self.rg,
                            "secret_key": None,
                        }
                    )
                    for uid, user_dict in users.items()
                }
            )

    def remove_user(self, user_dict):
        # --purge-keys is not really necessary, but still do it
        try:
            run.radosgw_admin(
                "user",
                "rm",
                "--uid",
                user_dict["uid"],
                "--purge-data",
                "--purge-keys",
            )
        except CalledProcessError as err:
            if (
                err.status_code == 2
                and user_dict["uid"] not in list_radosgw_users()
            ):
                # potential atomicity problem, but user is gone -> all good
                pass
            else:
                raise

    def purge_user_keys(self, uid: str):
        for key in run.json.radosgw_admin("user", "info", "--uid", uid)["keys"]:
            run.radosgw_admin("key", "rm", "--access-key", key["access_key"])

    def ensure_radosgw_user(self, uid: str, user_dict: dict, replace: bool):
        """Ensures that a radosgw user with the desired properties and keys exists.
        Called upon user creation, as well as when rotating keys."""

        has_keys = user_dict["access_key"] and user_dict["secret_key"]
        conditional_key_args = (
            (
                # fmt: off
                    "--access-key", user_dict["access_key"],
                    "--secret-key", user_dict["secret_key"],
                # fmt: on
            )
            if has_keys
            else ()
        )

        if not replace:
            if not has_keys:
                log.warn(
                    "user create: no access key pair provided, "
                    "this is likely a directory bug. "
                    "Proceeding nonetheless."
                )
            run.json.radosgw_admin(
                # fmt: off
                "user", "create",
                "--uid", uid,
                "--display-name", user_dict["display_name"],
                # Security Warning: by passing around the keys as command line
                # arguments, we potentially leak them via ps/ proc. This is
                # acceptable for now, as ceph hosts are accessible to admins only.
                # A preferential alternative would be the ability for `radosgw-admin`
                # to read from env variables. There's also the admin RESTful API of
                # radosgw, unfortunately that's based on S3 authentication logic.
                # Implementing this, e.g. via boto3, is rather complex and not a pleasure.
                *conditional_key_args,
                # fmt: on
            )
        else:
            # idempotent: always remove all keys and add new one
            self.purge_user_keys(uid)
            run.radosgw_admin(
                # fmt: off
                "user", "modify",
                "--uid", uid,
                "--display-name", user_dict["display_name"],
                *conditional_key_args,
                # fmt: on
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Flying Circus S3 usage accounting"
    )
    parser.add_argument(
        "-E",
        "--enc",
        default="/etc/nixos/enc.json",
        help="Path to enc.json (default: %(default)s)",
    )

    args = parser.parse_args()
    with open(args.enc) as f:
        enc = json.load(f)

    # TODO: do we need this?
    # init_logging(
    #    context.verbose, context.logdir, show_caller_info=show_caller_info
    # )

    directory = connect(enc, ring="max")
    location = enc["parameters"]["location"]

    # first do accounting based on the existing users, might be the last time
    # in case of user deletions.
    # accounting as a first but separate step is good,
    # because we want accounting to succeed independent from any additional
    # user management failures. Users pending deletion are accounted one last
    # time, users to be created are accounted first in the next run.
    got_errors = False
    try:
        accounting(location, directory)
    except Exception:
        log.exception("Error during S3 accounting, continuing with user sync:")

    user_manager = RadosgwUserManager(
        directory, location, enc["parameters"]["rg"]
    )
    user_manager.sync_users()
    got_errors = got_errors or user_manager.processing_errors

    # on errors, the service shall return a non-zero exit code to be caught by our monitoring
    return 2 if got_errors else 0


if __name__ == "__main__":
    sys.exit(main())
