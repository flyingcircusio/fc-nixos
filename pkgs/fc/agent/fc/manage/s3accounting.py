"""realises pending actions on S3 users based on directory data;
accountig for usage data"""

import argparse
import json
import subprocess

from fc.util.directory import connect
from fc.util.runners import run


def accounting(location: str, dir_conn):
    """Uploads usage data from Ceph/RadosGW into the Directory"""
    # TODO: only account users from the directory list?
    users = run.json.radosgw_admin("user", "list")

    usage = dict()
    for user in users:
        stats = run.json.radosgw_admin("user", "stats", "--uid", user)
        usage[user] = str(stats["stats"]["total_bytes"])

    dir_conn.store_s3(location, usage)


def main():
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

    directory = connect(enc, ring=0)

    # first do accounting based on the existing users, might be the last time
    # in case of user deletions.
    accounting(enc["parameters"]["location"], directory)


if __name__ == "__main__":
    main()
