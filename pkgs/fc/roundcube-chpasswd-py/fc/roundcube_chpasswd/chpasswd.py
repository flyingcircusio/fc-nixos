#!/usr/bin/env python3

import argparse
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-f",
        "--passwd-file",
        metavar="PATH",
        help="Path to password file to be updated",
        required=True,
    )

    args = parser.parse_args()
    line = sys.stdin.readline()
    data = line.strip().split(":")

    if len(data) != 2:
        raise RuntimeError("Input line must contain exactly one colon")

    user, passwd = data

    hashed = subprocess.check_output(
        ["mkpasswd", "-s", "-m", "yescrypt"],
        input=passwd.encode(),
    ).decode()

    # htpasswd will not create the file if it does not exist, so open
    # for creation beforehand.
    file = open(args.passwd_file, "a")

    subprocess.run(
        ["htpasswd", "-p", "-i", args.passwd_file, user],
        input=hashed.encode(),
        stderr=subprocess.DEVNULL,
        check=True,
    )

    file.close()
