#!/usr/bin/env python3
"""Resolver staleness check.

Determine whether a resolver is returning stale responses.

By default we use A records that are known to have a short TTL so that
we can get quick feedback if our resolver starts delivering stale
responses.

"""

import argparse
import subprocess
import sys


def stale():
    """Checks that kresd resolves targets correctly and without stale answers."""
    p = argparse.ArgumentParser()
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", default="53")
    p.add_argument(
        "--target",
        nargs="+",
        default=["dns-probe.flyingcircus.io", "www.google.com", "kernel.org"],
        help="One or more domain names to resolve for the check.",
    )
    args = p.parse_args()

    errors = []
    full_outputs = []

    for target in args.target:
        try:
            result = subprocess.run(
                [
                    "dig",
                    "-t", "A", target,
                    f"@{args.host}", "-p", args.port,
                    "+yaml",
                ],
                timeout=10,
                capture_output=True,
            )  # fmt: skip
        except subprocess.TimeoutExpired:
            errors.append(f"CRITICAL - dig command timed out for {target}.")
            continue

        output = result.stdout.decode("ascii", errors="ignore")
        stderr = result.stderr.decode("ascii", errors="ignore")
        full_outputs.append(
            f"--- Check for {target} ---\nSTDOUT:\n{output}\nSTDERR:\n{stderr}"
        )

        is_stale = "Stale Answer" in output
        has_result = "status: NOERROR" in output and " IN A " in output
        if result.returncode:
            errors.append(
                f"CRITICAL - dig returned non-zero exit code {result.returncode} for {target}."
            )
        elif not has_result:
            errors.append(
                f"CRITICAL - incorrect response received for {target}."
            )
        elif is_stale:
            errors.append(
                f"CRITICAL - correct but stale response received for {target}."
            )

    if not errors:
        print("OK - correct and non-stale responses received for all targets.")
        sys.exit(0)
    else:
        print("\n".join(errors))
        print()
        print("\n".join(full_outputs))
        sys.exit(2)


if __name__ == "__main__":
    stale()
