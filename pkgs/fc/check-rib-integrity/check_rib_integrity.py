#!/usr/bin/env python3
"""Check that the state of the FRR routing information base matches
the kernel network state.
"""

import argparse
import json
import subprocess
import sys
from ipaddress import IPv4Address, IPv4Interface, IPv4Network, IPv6Address


def ok(msg):
    print("OK - {}".format(msg))
    sys.exit(0)


def critical(msg, *context):
    print("CRITICAL - {}".format(msg))
    for line in context:
        print(line)
    sys.exit(2)


def fmtaddrs(addrs):
    return map(lambda x: str(x), sorted(addrs))


def json_cmd(*args, **kwargs):
    data = subprocess.check_output(*args, **kwargs)
    return json.loads(data.decode("utf-8"))


def vtysh_json(cmd):
    return json_cmd(["vtysh", "-c", cmd])


def ip_route_json(net):
    return json_cmd(["ip", "-j", "route", "show", "root", str(net)])


def bridge_macs(bridge, vxlan):
    # XXX: newer versions of iproute2 support bridge -j for json
    # output
    data = subprocess.check_output(["bridge", "fdb", "show", "br", bridge])
    data = [item.split() for item in data.decode("utf-8").splitlines()]
    data = [
        item
        for item in data
        # drop forwarding entries for vlan-aware bridges
        if "vlan" not in item
    ]

    local_macs = {
        item[0]: (item[2] if item[2] != vxlan else bridge)
        for item in data
        # extern_learn records managed by zebra, self records handled
        # internally by device drivers
        if "extern_learn" not in item and "self" not in item
        # ignore the mac addresses assigned to the host side of tap
        # interfaces, but include the mac address assigned to the
        # bridge interface
        and ("permanent" not in item or item[2] == vxlan)
    }

    remote_macs = {
        mac[0]: IPv4Address(dest[4])
        for mac in data
        if mac[2] == vxlan and mac[4] == "master" and mac[5] == bridge
        for dest in data
        if dest[0] == mac[0] and dest[2] == vxlan and dest[3] == "dst"
    }

    return local_macs, remote_macs


def zebra_macs(vni):
    data = vtysh_json(f"show evpn mac vni {vni} json")
    data = data["macs"]

    local_macs = {
        key: value["intf"]
        for key, value in data.items()
        if value["type"] == "local"
    }

    remote_macs = {
        key: IPv4Address(value["remoteVtep"])
        for key, value in data.items()
        if value["type"] == "remote"
    }

    return local_macs, remote_macs


def vtysh_load_evpn_rib():
    data = vtysh_json("show bgp l2vpn evpn route detail type 2 json")

    macs = [
        (
            path["vni"],
            route["mac"],
            (
                {
                    IPv4Address(hop["ip"])
                    for hop in path["nexthops"]
                    if "used" in hop and hop["used"]
                }
                if path["aspath"]["segments"]
                else {}
            ),
        )
        for rd in data.values()
        if isinstance(rd, dict)  # note: type heterogeneity in vtysh json!
        for route in rd.values()
        if isinstance(route, dict)
        for paths in route["paths"]
        for path in paths
        if path["valid"]
        and "bestpath" in path
        and "overall" in path["bestpath"]
        and path["bestpath"]["overall"]
    ]

    return {
        int(outer_vni): {
            mac: hops for inner_vni, mac, hops in macs if inner_vni == outer_vni
        }
        for outer_vni in {mac[0] for mac in macs}
    }


def bgpd_macs(rib, vni):
    if vni not in rib:
        return {}, {}

    macs = rib[vni]

    local_macs = {mac for mac, nexthops in macs.items() if not nexthops}
    remote_macs = {mac: nexthops for mac, nexthops in macs.items() if nexthops}

    return local_macs, remote_macs


def check_unicast_rib(args):
    fib = {}

    for prefix in args.prefixes:
        data = ip_route_json(prefix)
        data = list(
            filter(lambda x: "protocol" in x and x["protocol"] == "bgp", data)
        )

        dests = list(map(lambda entry: entry["dst"], data))
        if len(set(dests)) != len(dests):
            critical(
                "duplicate addresses in kernel routing table",
                "duplicate-kernel-address {}".format(" ".join(fmtaddrs(dests))),
            )

        for entry in data:
            dest = IPv4Address(entry["dst"])
            if dest not in prefix:
                raise RuntimeError(
                    f"ip route returned route for {dest} outside of queried prefix {prefix}"
                )
            nexthops = list()
            if "via" in entry:
                nexthops.append(IPv6Address(entry["via"]["host"]))
            elif "nexthops" in entry:
                for hop in entry["nexthops"]:
                    nexthops.append(IPv6Address(hop["via"]["host"]))

            if len(set(nexthops)) != len(nexthops):
                raise RuntimeError(
                    "ip route return duplicate nexthop for {}: {}".format(
                        dest, ", ".join(fmtaddrs(nexthops))
                    )
                )

            fib[dest] = set(nexthops)

    data = vtysh_json("show bgp ipv4 unicast json")

    rib = {}

    for prefix, paths in data["routes"].items():
        dest = IPv4Network(prefix, strict=True)
        if dest.prefixlen != 32 or not any(
            map(lambda arg: arg.supernet_of(dest), args.prefixes)
        ):
            continue

        paths = [
            p
            for p in paths
            if p["valid"]
            and (
                ("bestpath" in p and p["bestpath"])
                or ("multipath" in p and p["multipath"])
            )
            # ignore locally announced routes
            and p["path"] != ""
        ]

        if not paths:
            continue

        nexthops = [
            IPv6Address(n["ip"])
            for p in paths
            for n in p["nexthops"]
            if "used" in n and n["used"]
        ]

        if len(set(nexthops)) != len(nexthops):
            raise RuntimeError(
                "vtysh returned duplicate nexthop for {}: {}".format(
                    dest, ", ".join(fmtaddrs(nexthops))
                )
            )

        rib[dest.network_address] = set(nexthops)

    mismatches = set()
    context = list()

    rib_only = set(rib.keys()) - set(fib.keys())
    fib_only = set(fib.keys()) - set(rib.keys())
    if rib_only or fib_only:
        mismatches.add("addresses")
    if rib_only:
        context.append(
            "extra-frr-addresses {}".format(" ".join(fmtaddrs(rib_only)))
        )
    if fib_only:
        context.append(
            "extra-kernel-addresses {}".format(" ".join(fmtaddrs(fib_only)))
        )

    neighdiff = dict()
    for addr in set(rib.keys()).intersection(set(fib.keys())):
        ribhops = rib[addr]
        fibhops = fib[addr]

        rib_only = ribhops - fibhops
        fib_only = fibhops - ribhops

        if rib_only or fib_only:
            mismatches.add("nexthops")
        if rib_only:
            context.append(
                "extra-frr-nexthops {} {}".format(
                    addr, ",".join(fmtaddrs(rib_only))
                )
            )
        if fib_only:
            context.append(
                "extra-kernel-nexthops {} {}".format(
                    addr, ",".join(fmtaddrs(fib_only))
                )
            )

    if mismatches:
        critical(
            "mismatching {} between frr and kernel".format(
                " and ".join(mismatches)
            ),
            *sorted(context),
        )
    else:
        ok("addresses and nexthop in frr and kernel match")


def check_evpn_rib(args):
    mismatches = set()
    context = list()

    evpn_rib = vtysh_load_evpn_rib()

    for vni in args.vnis:
        # discover bridge and vxlan interface for the vni
        data = vtysh_json(f"show evpn vni {vni} json")
        bridge = data["sviInterface"]
        vxlan = data["vxlanInterface"]

        bridge_local, bridge_remote = bridge_macs(bridge, vxlan)
        zebra_local, zebra_remote = zebra_macs(vni)
        bgpd_local, bgpd_remote = bgpd_macs(evpn_rib, vni)

        # compare local mac state in kernel and zebra
        bridge_only = set(bridge_local.keys()) - set(zebra_local.keys())
        zebra_only = set(zebra_local.keys()) - set(bridge_local.keys())
        if bridge_only or zebra_only:
            mismatches.add("zebra and kernel (local macs)")
        if bridge_only:
            context.append(
                "zebra-missing-kernel-macs {} {}".format(
                    bridge, " ".join(sorted(bridge_only))
                )
            )
        if zebra_only:
            context.append(
                "zebra-macs-not-in-kernel {} {}".format(
                    bridge, " ".join(sorted(zebra_only))
                )
            )

        for mac in set(bridge_local.keys()).intersection(
            set(zebra_local.keys())
        ):
            if bridge_local[mac] != zebra_local[mac]:
                mismatches.add("zebra and kernel (bridge port)")
                context.append(
                    "zebra-incorrect-bridge-port {} {} kernel {} zebra {}".format(
                        bridge, mac, bridge_local[mac], zebra_local[mac]
                    )
                )

        # compare remote mac state in kernel and zebra
        bridge_only = set(bridge_remote.keys()) - set(zebra_remote.keys())
        zebra_only = set(zebra_remote.keys()) - set(bridge_remote.keys())
        if bridge_only or zebra_only:
            mismatches.add("zebra and kernel (remote macs)")
        if bridge_only:
            context.append(
                "kernel-macs-not-in-zebra {} {}".format(
                    bridge, " ".join(sorted(bridge_only))
                )
            )
        if zebra_only:
            context.append(
                "kernel-missing-zebra-macs {} {}".format(
                    bridge, " ".join(sorted(zebra_only))
                )
            )

        for mac in set(bridge_remote.keys()).intersection(
            set(zebra_remote.keys())
        ):
            if bridge_remote[mac] != zebra_remote[mac]:
                mismatches.add("zebra and kernel (remote vteps)")
                context.append(
                    "kernel-incorrect-vtep-address {} {} kernel {} zebra {}".format(
                        bridge,
                        mac,
                        str(bridge_remote[mac]),
                        str(zebra_remote[mac]),
                    )
                )

        # compare local mac state in kernel and bgpd
        bridge_only = set(bridge_local.keys()) - bgpd_local
        bgpd_only = bgpd_local - set(bridge_local.keys())
        if bridge_only or bgpd_only:
            mismatches.add("bgpd and kernel (local macs)")
        if bridge_only:
            context.append(
                "bgpd-missing-kernel-macs {} {}".format(
                    bridge, " ".join(sorted(bridge_only))
                )
            )
        if bgpd_only:
            context.append(
                "bgpd-macs-not-in-kernel {} {}".format(
                    bridge, " ".join(sorted(bgpd_only))
                )
            )

        # sanity check bgpd remote mac state
        bgpd_multi_remote_macs = {
            mac: addrs for mac, addrs in bgpd_remote.items() if len(addrs) > 1
        }
        if bgpd_multi_remote_macs:
            mismatches.add("bgpd duplicate remote nexthops")
            for mac, addrs in bgpd_multi_remote_macs:
                context.append(
                    "bgpd-duplicate-remote-nexthop {} {} {}".format(
                        bridge, mac, " ".join(fmtaddrs(addrs))
                    )
                )
        bgpd_remote = {mac: addrs.pop() for mac, addrs in bgpd_remote.items()}

        # compare remote mac state in kernel and bgpd
        bridge_only = set(bridge_remote.keys()) - set(bgpd_remote.keys())
        bgpd_only = set(bgpd_remote.keys()) - set(bridge_remote.keys())
        if bridge_only or bgpd_only:
            mismatches.add("bgpd and kernel (remote macs)")
        if bridge_only:
            context.append(
                "kernel-macs-not-in-bgpd {} {}".format(
                    bridge, " ".join(sorted(bridge_only))
                )
            )
        if bgpd_only:
            context.append(
                "kernel-missing-bgpd-macs {} {}".format(
                    bridge, " ".join(sorted(bgpd_only))
                )
            )

        for mac in set(bridge_remote.keys()).intersection(
            set(bgpd_remote.keys())
        ):
            if bridge_remote[mac] != bgpd_remote[mac]:
                mismatches.add("bgpd and kernel (remote vteps)")
                context.append(
                    "kernel-incorrect-vtep-address {} {} kernel {} bgpd {}".format(
                        bridge,
                        mac,
                        str(bridge_remote[mac]),
                        str(bgpd_remote[mac]),
                    )
                )

    if mismatches:
        critical(
            "mismatches between EVPN RIB and FIB: {}".format(
                ", ".join(mismatches)
            ),
            *sorted(context),
        )
    else:
        ok("EVPN RIB and FIB state match")

    print(mismatches)
    for line in context:
        print(line)


def main():
    parser = argparse.ArgumentParser(prog="check_rib_integrity")
    subparsers = parser.add_subparsers(required=True, dest="command")

    unicast_parser = subparsers.add_parser(
        "check-unicast-rib", help="Check the status of the IPv4 unicast RIB"
    )
    unicast_parser.set_defaults(func=check_unicast_rib)
    unicast_parser.add_argument(
        "-p",
        "--prefix",
        metavar="PREFIX",
        action="append",
        dest="prefixes",
        required=True,
        type=lambda s: IPv4Network(s, True),
        help="Underlay IPv4 prefix",
    )

    evpn_parser = subparsers.add_parser(
        "check-evpn-rib", help="Check the status of the L2VPN EVPN RIB"
    )
    evpn_parser.set_defaults(func=check_evpn_rib)
    evpn_parser.add_argument(
        "-n",
        "--vni",
        metavar="IFACE",
        action="append",
        dest="vnis",
        type=int,
        required=True,
        help="EVPN VNI number",
    )

    args = parser.parse_args()

    args.func(args)


if __name__ == "__main__":
    main()
