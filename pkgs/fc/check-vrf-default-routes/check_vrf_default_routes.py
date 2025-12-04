#!/usr/bin/env python3
"""Check vrfpub default route presence."""

import argparse
import json
import subprocess
import sys


def get_routing_table(ip_version, vrf):
    output = subprocess.check_output(
        ["ip", "-json", f"-{ip_version}", "route", "show", "vrf", vrf]
    )
    return json.loads(output.decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(prog="check_vrf_default_routes")
    parser.add_argument("vrfs", metavar="VRFS", nargs="+", help="VRFs to check")

    args = parser.parse_args()

    oks = set()
    errors = set()

    for vrf in args.vrfs:
        for version in ["4", "6"]:
            for route in get_routing_table(version, vrf):
                if route["dst"] == "default":
                    oks.add(f"{vrf}: default route for IPv{version} found")
                    break
            else:
                errors.add(f"{vrf}: no default route found for IPv{version}")

    if errors:
        print(f"{len(errors)} CHECKS CRITICAL - vrf is missing default routes")
    else:
        print(f"{len(oks)} CHECKS OK - vrfs have expected default routes")

    for msg in errors:
        print(f"ERROR - {msg}")
    for msg in oks:
        print(f"OK - {msg}")

    if errors:
        sys.exit(2)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
