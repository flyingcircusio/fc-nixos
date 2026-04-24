import logging
import subprocess
from dataclasses import dataclass
from subprocess import CalledProcessError

from fc.util.runners import run

log = logging.getLogger()


def list_radosgw_users() -> list[str]:
    """List all uids of users known to the local radosgw"""
    return run.json.radosgw_admin("user", "list")


class RGWState:
    uid: str
    display_name: str | None = None
    access_key: str | None = None
    secret_key: str | None = None

    key_count = 0

    exists = False

    def __init__(self, uid):
        self.uid = uid

    def update(self, previously_deleted=False):
        def check_user_doesnt_exist(code, stdout, stderr):
            return (
                code == 22
                and b"could not fetch user info: no user info saved" in stderr
            )

        try:
            state = run.json.radosgw_admin(
                "user",
                "info",
                "--uid",
                self.uid,
                # silence error when the user was previously deleted
                silent_errors=lambda code, stdout, stderr: (
                    previously_deleted
                    and check_user_doesnt_exist(code, stdout, stderr)
                ),
            )

        except subprocess.CalledProcessError as e:
            if check_user_doesnt_exist(e.returncode, e.stdout, e.stderr):
                self.exists = False
                self.display_name = None
                self.key_count = 0
                self.access_key = None
                self.secret_key = None
            else:
                # We have an inconsistent state now.
                # We could still handle other users, but we have no consistent state to report to the directory,
                # so raise the error and break loud.
                raise
        else:
            self.exists = True
            self.display_name = state["display_name"]

            self.key_count = len(state["keys"])

            try:
                # we silently ignore any additional keys here, logging this case is
                # left to an explicit check method.
                main_key = state["keys"][0]
            except IndexError:
                self.access_key = None
                self.secret_key = None
            else:
                self.access_key = main_key["access_key"]
                self.secret_key = main_key["secret_key"]

    def ensure_deleted(self):
        if not self.exists:
            return
        try:
            # --purge-keys is not really necessary, but still do it
            run.radosgw_admin(
                "user", "rm",
                "--uid", self.uid,
                "--purge-data",
                "--purge-keys",
            )  # fmt: skip
        except CalledProcessError as err:
            if err.returncode == 2 and self.uid not in list_radosgw_users():
                # potential atomicity problem, but user is gone -> all good
                pass
            else:
                raise
        self.update(previously_deleted=True)

    def ensure_exists(
        self, display_name: str, access_key: str, secret_key: str
    ):
        """Ensures that a radosgw user with the desired properties and keys exists.

        Called upon user creation, as well as when rotating key or information.

        """
        if not secret_key:
            raise RuntimeError(
                "user ensure_exists: secret key must be provided"
            )
        if not self.exists:
            run.radosgw_admin(
                "user", "create",
                "--uid", self.uid,
                "--display-name", display_name,
                # Security Warning: by passing around the keys as command line
                # arguments, we potentially leak them via ps/ proc. This is
                # acceptable for now, as ceph hosts are accessible to admins only.
                # A preferential alternative would be the ability for `radosgw-admin`
                # to read from env variables. There's also the admin RESTful API of
                # radosgw, unfortunately that's based on S3 authentication logic.
                # Implementing this, e.g. via boto3, is rather complex and not a pleasure.
                "--access-key", access_key,
                "--secret-key", run.redacted(secret_key)
            )  # fmt: skip
            self.update()
        # we only modify the keys if we have the secret available
        # only modify/ add keys when we have sufficient data:
        update_args: list[str] = []
        if self.display_name != display_name:
            update_args += ["--display-name", display_name]
        if secret_key and secret_key != self.secret_key:
            update_args += ["--access-key", access_key]
            update_args += ["--secret-key", run.redacted(secret_key)]
        if update_args:
            run.radosgw_admin(
                "user", "modify",
                "--uid", self.uid,
                *update_args,
            )  # fmt: skip
            self.update()

    def ensure_no_keys(self):
        """Remove _all_ keys to make users aware of the impending hard deletion."""
        keys = run.json.radosgw_admin("user", "info", "--uid", self.uid)["keys"]
        for key in keys:
            run.radosgw_admin("key", "rm", "--access-key", key["access_key"])
        if keys:
            self.update()


@dataclass
class DirectoryState:
    uid: str
    display_name = None
    access_key = None
    secret_key = None
    deletion_stages: list[str]
    exists = False
    key_count = 1  # We always expect exactly 1 key for now.

    def __init__(self, uid: str):
        self.uid = uid
        self.deletion_stages = []

    def update(self, user_dict):
        self.exists = True
        self.display_name = user_dict["display_name"]
        self.access_key = user_dict["access_key"]
        self.secret_key = user_dict["secret_key"]
        self.deletion_stages = user_dict["deletion"]["stages"]


class User:
    def __init__(self, uid: str):
        self.uid = uid
        self.rgw = RGWState(uid)
        self.directory = DirectoryState(uid)

    @property
    def should_exist(self):
        return self.directory.exists and not self.should_be_deleted

    @property
    def should_be_deleted(self):
        return "hard" in self.directory.deletion_stages

    def ensure(self):
        if self.should_exist:
            if "soft" in self.directory.deletion_stages:
                # We want to ensure that the user exists
                self.rgw.ensure_exists(
                    self.directory.display_name,
                    self.directory.access_key,
                    self.directory.secret_key,
                )
                self.rgw.ensure_no_keys()
            else:
                self.rgw.ensure_exists(
                    self.directory.display_name,
                    self.directory.access_key,
                    self.directory.secret_key,
                )
        elif self.should_be_deleted:
            self.rgw.ensure_deleted()

    def compare_states(self):
        compare_properties = ("display_name", "access_key", "key_count")
        for name in compare_properties:
            rgw_value = getattr(self.rgw, name)
            directory_value = getattr(self.directory, name)
            if rgw_value != directory_value:
                yield (
                    f"- Differing {name}: "
                    f"RGW has {rgw_value!r}, directory has {directory_value!r}"
                )

    def validate(self) -> bool:
        mismatches: list[str] = []

        if self.should_exist:
            if self.rgw.exists:
                if "soft" not in self.directory.deletion_stages:
                    # In soft deletion state we don't care whether the attributes are
                    # correct. Specifically the key count won't match.
                    mismatches.extend(self.compare_states())
            else:
                mismatches.append("- not found in local users")
        else:
            if self.rgw.exists:
                mismatches.append(
                    "- is not known in the directory but exists (unmanaged) in RGW"
                )

        if mismatches:
            log.error(
                f"User data mismatch for {self.uid}:\n"
                + "\n\t".join(mismatches)
            )
            return False
        else:
            return True


class UserManager:
    users: dict[str, User]

    def __init__(self, directory_connection, location: str, rg: str):
        self.dir_conn = directory_connection
        self.location = location
        self.rg = rg
        self.processing_errors = False
        self.users = {}

        # Get the desired state from the directory
        directory_info = self.dir_conn.list_s3_users()
        for uid, user_dict in directory_info.items():
            # Safety-belt: ensure we're acting on the right users. Distinct
            # RGW instances can carry the same user names twice and I'd like to
            # absolutely make sure that we never ever locally delete a user
            # that was marked for deletion in a different cluster.
            assert user_dict["location"] == self.location, (
                "Encountered user from unexpected location: "
                + user_dict["location"]
            )
            assert user_dict["storage_resource_group"] == self.rg, (
                "Encountered user from unexpected storage resource group: "
                + user_dict["storage_resource_group"]
            )
            user = self.get_user(uid)
            user.directory.update(user_dict)

        # Get user objects for all local users
        for uid in list_radosgw_users():
            user = self.get_user(uid)
            user.rgw.update()

    def get_user(self, uid) -> User:
        return self.users.setdefault(uid, User(uid))

    def report_local_users_to_directory(self):
        self.dir_conn.update_s3_users(
            {
                user.uid: {
                    "display_name": user.rgw.display_name,
                    "access_key": user.rgw.access_key,
                    # directory ring0 API wants to have RG and location
                    # as explicit values
                    "location": self.location,
                    "storage_resource_group": self.rg,
                    "secret_key": user.rgw.secret_key,
                }
                for user in self.users.values()
                if user.rgw.exists
            }
        )

    def sync_users(self):
        for user in self.users.values():
            try:
                user.ensure()
                user.validate()
            except Exception:
                # individual errors shall not block progress on all other users
                log.exception(
                    f"Encountered an error while handling {user.uid}, continuing:"
                )
                self.processing_errors = True

        # report all users present with uid, display_name, access_key, and secret_key
        self.report_local_users_to_directory()


class RgwUserManager:
    """small subsystem class, serving as abstraction entry points for the fc-ceph
    VersionedSubsystem dispatching
    """

    @staticmethod
    def init_usermanager(
        directory_connection, location: str, rg: str
    ) -> UserManager:
        return UserManager(directory_connection, location, rg)

    @staticmethod
    def accounting(location: str, dir_conn):
        """Uploads usage data from Ceph/RadosGW into the Directory"""
        users = list_radosgw_users()

        usage = dict()
        for user in users:
            try:
                stats = run.json.radosgw_admin(
                    "user",
                    "stats",
                    "--uid",
                    user,
                    silent_errors=(
                        lambda code, stdout, stderr: (
                            code == 2
                            and b"User has not been initialized or user does not exist"
                            in stderr
                        )
                    ),
                )
                usage[user] = str(stats["stats"]["total_bytes"])
            except CalledProcessError as e:
                logging.error(f"Could not get user statistics: {e.stderr}")
        dir_conn.store_s3(location, usage)
