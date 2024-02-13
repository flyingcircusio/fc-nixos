"""Uploads usage data from Ceph/RadosGW into the Directory"""

import argparse
import json
import subprocess

from fc.util.directory import connect


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

    result = subprocess.run(
        ["radosgw-admin", "user", "list"], check=True, capture_output=True
    )
    users = json.loads(result.stdout)

    usage = dict()
    for user in users:
        result = subprocess.run(
            ["radosgw-admin", "user", "stats", "--uid", user],
            check=True,
            capture_output=True,
        )
        stats = json.loads(result.stdout)
        usage[user] = str(stats["stats"]["total_bytes"])

    location = enc["parameters"]["location"]

    directory = connect(enc, ring=0)
    directory.store_s3(location, usage)


if __name__ == "__main__":
    main()
