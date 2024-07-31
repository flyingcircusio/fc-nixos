#!/usr/bin/env python3
"""Check that two or more host network interfaces are connected to
different switches.
"""

import argparse
import json
import subprocess
import sys


def lldpctl(iface):
    data = subprocess.check_output(["lldpctl", "-f", "json", iface])
    return json.loads(data.decode("utf-8"))


def main():
    parser = argparse.ArgumentParser(prog="check_link_redundancy")
    parser.add_argument(
        "interfaces", metavar="IFACES", nargs="+", help="Interfaces to check"
    )

    args = parser.parse_args()
    switches_all = list()
    switches_unique = set()

    for iface in args.interfaces:
        data = lldpctl(iface)
        data = data["lldp"]
        if (
            "interface" in data
            and iface in data["interface"]
            and "chassis" in data["interface"][iface]
        ):
            data = data["interface"][iface]["chassis"]
            switches_all.append(data.keys())
            switches_unique.update(data.keys())

    if len(switches_all) != len(args.interfaces):
        print("CRITICAL - interfaces are missing visible peer devices in LLDP ")
        sys.exit(2)
    elif len(switches_all) != len(switches_unique):
        print("CRITICAL - multiple interfaces are connected to the same switch")
        sys.exit(2)
    else:
        print("OK - interfaces are connected to different switches")
        sys.exit(0)


if __name__ == "__main__":
    main()
