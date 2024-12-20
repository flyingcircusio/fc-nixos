#!/usr/bin/env python3
"""Collect information over the number of routes in the kernel.

This script collects information on the number of routes in the
kernel, separately counting the number of single-path and multi-path
routes. Unreachable routes are ignored and onlink/device routes are
considered single-path routes.

"""

import json
import subprocess
import sys


def count_routes(type_flag):
    raw = subprocess.check_output(["ip", "-j", type_flag, "route", "show"])
    data = json.loads(raw.decode("utf-8"))

    multi = 0
    single = 0

    for route in data:
        if "type" in route and route["type"] == "unreachable":
            continue
        if "nexthops" in route:
            multi += 1
        else:
            single += 1

    return (single, multi)


def main():
    path_labels = ["single", "multi"]
    family_labels = ["ipv4", "ipv6"]
    data = (count_routes("-4"), count_routes("-6"))

    result = list()
    for path_idx, path_label in enumerate(path_labels):
        for family_idx, family_label in enumerate(family_labels):
            result.append(
                {
                    "name": "routes",
                    "family": family_label,
                    "path": path_label,
                    "count": data[family_idx][path_idx],
                }
            )

    print(json.dumps(result))


if __name__ == "__main__":
    main()
