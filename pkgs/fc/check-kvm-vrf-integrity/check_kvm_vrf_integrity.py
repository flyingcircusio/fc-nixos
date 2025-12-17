#!/usr/bin/env python3
"""Check KVM VRF guest routes are announced correctly."""

import argparse
import json
import subprocess
import sys

ROUTE_PROTO = "fc-qemu"


def json_cmd(*args, **kwargs):
    data = subprocess.check_output(*args, **kwargs)
    return json.loads(data.decode("utf-8"))


def vtysh_cmd(cmd):
    return json_cmd(["vtysh", "-c", cmd])


def vtysh_vni(table):
    return vtysh_cmd(f"show bgp l2vpn evpn vni {table} json")


def vtysh_routes(key):
    return vtysh_cmd(f"show bgp l2vpn evpn rd {key} json")


def kvm_routes(ip_version, table):
    return json_cmd(
        [
            "ip",
            "-j",
            f"-{ip_version}",
            "route",
            "show",
            "table",
            f"{table}",
            "proto",
            ROUTE_PROTO,
        ]
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "tables",
        metavar="table",
        nargs="+",
        type=int,
        help="Table IDs of VRFs to check",
    )

    args = parser.parse_args()

    oks = set()
    warnings = set()
    errors = set()

    for table in args.tables:
        kernel_routes = []
        for version in [4, 6]:
            kernel_routes.extend(kvm_routes(version, table))

        kernel_routes = {x["dst"] for x in kernel_routes}

        vni = vtysh_vni(table)
        if "rd" not in vni:
            errors.add(f"table {table}: could not find RD for VNI in FRR")
            continue

        rd = vni["rd"]
        frr_routes = vtysh_routes(rd)

        if rd in frr_routes:
            frr_routes = frr_routes[rd]
            frr_routes = {
                path["ip"]
                for route in frr_routes.values()
                if isinstance(route, dict)
                for path in route["paths"]
            }
        else:
            frr_routes = set()

        if kernel_routes.difference(frr_routes):
            errors.add(
                f"table {table}: FRR announcing {len(frr_routes)} "
                f"of {len(kernel_routes)} kernel routes"
            )
        elif frr_routes.difference(kernel_routes):
            warnings.add(
                f"table {table}: FRR announcing {len(frr_routes)} routes, "
                f"{len(kernel_routes)} exist in kernel"
            )
        else:
            oks.add(
                f"table {table}: FRR and kernel routing table match "
                f"({len(kernel_routes)} routes)"
            )

    if errors:
        print(
            f"{len(errors)} CHECKS CRITICAL - VRF routes not announced properly"
        )
    elif warnings:
        print(f"{len(warnings)} CHECKS WARNING - extra VRF routes announced")
    else:
        print(f"{len(oks)} CHECKS OK - VRF routes announced as expected")

    for msg in sorted(errors):
        print(f"ERROR - {msg}")
    for msg in sorted(warnings):
        print(f"WARNING - {msg}")
    for msg in sorted(oks):
        print(f"OK - {msg}")

    if errors:
        sys.exit(2)
    elif warnings:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == "__main__":
    main()
