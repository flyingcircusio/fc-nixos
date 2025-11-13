#!/usr/bin/env python3
"""Check vrfpub default route presence."""

import json
import subprocess
import sys


def get_routing_table(ip_version):
    output = subprocess.check_output(
        ["ip", "-json", f"-{ip_version}", "route", "show", "vrf", "vrfpub"]
    )
    return json.loads(output.decode("utf-8"))


def main():
    oks = set()
    errors = set()

    for version in ["4", "6"]:
        for route in get_routing_table(version):
            if route["dst"] == "default":
                oks.add(f"default route for IPv{version} found")
                break
        else:
            errors.add(f"no default route found for IPv{version}")

    if errors:
        print(
            f"{len(errors)} CHECKS CRITICAL - PUB vrf is missing default routes"
        )
    else:
        print(f"{len(oks)} CHECKS OK - PUB vrf has expected default routes")

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
