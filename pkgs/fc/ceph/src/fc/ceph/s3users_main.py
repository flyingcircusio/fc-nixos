"""S3 user-oriented actions:

- update users based on directory data
- report accounting for usage

"""

import argparse
import datetime
import json
import logging
import sys
from pathlib import Path

import fc.ceph.s3users
from fc.ceph import Environment
from fc.util.directory import connect

log = logging.getLogger()
STAMP_FILE_PATH = Path("/var/log/fc-ceph-rgw-users-stamp.log")
CONFIG_FILE_PATH = Path("/etc/ceph/fc-ceph.conf")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Flying Circus S3 user management and accounting"
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

    directory = connect(enc, ring="max")
    location = enc["parameters"]["location"]

    environment = Environment(CONFIG_FILE_PATH)
    RgwUserManager = environment.prepare(fc.ceph.s3users.RgwUserManager)

    # Accounting first, based on the currently existing users: ensure users
    # that are deleted are accounted as accurately as possible. Users that
    # are about to be created will be accounted in the next run - they can't
    # possibly consume anything right now anyway.
    got_errors = False
    try:
        RgwUserManager.accounting(location, directory)
    except Exception:
        log.exception("Error during accounting:")
        got_errors = True
        log.warning("Continuing user management despite accounting errors.")

    user_manager = RgwUserManager.init_usermanager(
        directory, location, enc["parameters"]["resource_group"]
    )
    user_manager.sync_users()
    got_errors = got_errors or user_manager.processing_errors

    if not got_errors:
        STAMP_FILE_PATH.write_text(str(datetime.datetime.now()) + "\n")

    # on errors, the service shall return a non-zero exit code to be caught by
    # our monitoring
    return 2 if got_errors else 0


if __name__ == "__main__":
    sys.exit(main())
