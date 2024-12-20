#!/usr/bin/env python3

"""A convenience wrapper around ipmitool."""

import argparse
import os
import shutil

a = argparse.ArgumentParser(description=__doc__)
a.add_argument(
    "--user",
    "-U",
    default="ADMIN",
    help="User to connect with",
)
a.add_argument(
    "host",
    help="host to connect with",
)
a.add_argument(
    "args",
    nargs="*",
    help="host to connect with",
)

args = a.parse_args()

host = args.host
if "." not in args.host:
    location = os.environ["FCIO_LOCATION"]
    host = f"{host}.ipmi.{location}.gocept.net"

exec_args = [
    "ipmitool",
    "-4",
    "-U",
    args.user,
    "-I",
    "lanplus",
    "-H",
    host,
    *args.args,
]

exec_path = shutil.which("ipmitool")
print(exec_path, " ".join(exec_args))
os.execve(exec_path, exec_args, os.environ)
