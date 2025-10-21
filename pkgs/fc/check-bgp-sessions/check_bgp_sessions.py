#!/usr/bin/env python3
"""Check that FRR BGP sessions are up."""

import argparse
import json
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-i",
        "--interface",
        dest="interfaces",
        action="append",
        default=[],
        help="Check BGP session for named interface",
    )
    parser.add_argument(
        "-c",
        "--critical-age",
        default=60,
        metavar="SECONDS",
        help="Report critical status if session not in established state for longer than SECONDS seconds",
    )

    args = parser.parse_args()

    data = subprocess.check_output(["vtysh", "-c", "show bgp summary json"])
    data = json.loads(data.decode("utf-8"))
    data = data["ipv4Unicast"]["peers"]

    oks = set()
    errors = {}
    warnings = {}
    for iface in args.interfaces:
        if iface not in data:
            errors.update({iface: "no bgp session configured for interface"})
            continue

        if data[iface]["state"] == "Established":
            oks.add(iface)
            continue

        age = int(data[iface]["peerUptimeMsec"] / 1000)

        if age <= args.critical_age:
            warnings.update(
                {iface: f"bgp session not established since {age} seconds"}
            )
        else:
            errors.update(
                {iface: f"bgp session not established since {age} seconds"}
            )

    if errors:
        print("SESSIONS CRITICAL - {}".format(", ".join(errors.keys())))
    elif warnings:
        print("SESSIONS WARNING - {}".format(", ".join(warnings.keys())))
    else:
        print("SESSIONS OK - {}".format(", ".join(args.interfaces)))

    for iface, error in errors.items():
        print(f"CRITICAL {iface}: {error}")
    for iface, warning in warnings.items():
        print(f"WARN {iface}: {warning}")
    for iface in oks:
        print(f"OK {iface}")

    if errors:
        sys.exit(2)
    elif warnings:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
