#!/usr/bin/env python3
"""Knot resolver % check.

The main feature of this check is:

- detect whether the locally running kresd is
- allow selecting specific metrics to match

Could be / should be adapted to a plugin library at some point.
"""

import argparse
import subprocess
import sys


def stale():
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", default="1053")
    p.add_argument("--target", default="dummy.flyingcircus.io")
    args = p.parse_args()

    result = subprocess.run(
        [
            "dig",
            "-t", "A",
            args.target,
            f"@{args.host}", "-p", args.port,
            "+yaml",
        ],
        timeout=10,
        capture_output=True,
    )  # fmt: skip

    output = result.stdout.decode("ascii", errors="ignore")

    is_stale = "Stale Answer" in output
    has_result = "IN A 127.0.0.1" in output

    if has_result and not is_stale and not result.returncode:
        print("OK - correct and non-stale response received.")
        exit_code = 0
    elif not has_result:
        print("CRITICAL - incorrect response received.")
        exit_code = 2
    elif is_stale:
        print("CRITICAL - correct but stale response received.")
        exit_code = 2
    elif result.return_code:
        print("CRITICAL - unexpected return code received")
        exit_code = 2

    print()
    print(output)
    print(result.stderr.decode("ascii", errors="ignore"))

    sys.exit(exit_code)


if __name__ == "__main__":
    stale()
