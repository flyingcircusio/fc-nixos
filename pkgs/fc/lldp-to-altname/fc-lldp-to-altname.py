#!/usr/bin/env python3

import argparse
import json
import re
import socket
import subprocess
import sys

ALTNAME_PREFIX = "connected-switch-"
KNOWN_PREFIXES = ["ul-port-", ALTNAME_PREFIX]


def has_known_prefix(name):
    for prefix in KNOWN_PREFIXES:
        if name.startswith(prefix):
            return True
    return False


def quote_altname(name):
    return re.sub(r"[^a-z0-9A-Z]+", "-", name)


class Runner(object):
    def __init__(self, args):
        self.quiet = args.quiet
        self.dry_run = args.dry_run

        # canonicalise interface names
        indices = set()
        for iface in args.interfaces:
            try:
                index = socket.if_nametoindex(iface)
            except OSError as ex:
                print(
                    "Could not find interface by name: {}: {}".format(
                        iface, ex
                    ),
                    file=sys.stderr,
                )
                continue
            indices.add(index)

        interfaces = set()
        for index in indices:
            try:
                iface = socket.if_indextoname(index)
            except OSError as ex:
                print(
                    "Could not find interface by index: {}: {}".format(
                        index, ex
                    ),
                    file=sys.stderr,
                )
                continue
            interfaces.add(iface)

        # sort to ensure stable renames in case of altname collisions
        self.interfaces = sorted(list(interfaces))

    def check_json_output(self, *args):
        if not self.quiet:
            print("$ {}".format(" ".join(args)))
        data = subprocess.check_output(args)
        return json.loads(data.decode("utf-8"))

    def cmd(self, *args):
        if not self.quiet:
            print("$ {}".format(" ".join(args)))
        if not self.dry_run:
            subprocess.run(args, check=True)

    def run(self):
        oldnames = dict()
        lldpnames = dict()
        for iface in self.interfaces:
            oldnames[iface] = set()
            data = self.check_json_output("ip", "-j", "link", "show", iface)
            for datum in data:
                names = [
                    name
                    for name in datum.get("altnames", [])
                    if has_known_prefix(name)
                ]
                oldnames[iface].update(names)

            lldpnames[iface] = set()
            data = self.check_json_output("lldpctl", "-f", "json", iface)
            data = data["lldp"]
            if (
                "interface" in data
                and iface in data["interface"]
                and "chassis" in data["interface"][iface]
            ):
                switch_name = list(data["interface"][iface]["chassis"])[0]
                port_name = data["interface"][iface]["port"]["id"]["value"]
                lldpnames[iface].update(
                    [quote_altname(f"{switch_name}-port-{port_name}")]
                )

        newnames = dict()
        for iface in self.interfaces:
            newnames[iface] = set(
                map(lambda n: ALTNAME_PREFIX + n, lldpnames[iface])
            )
            newnames[iface].discard(iface)

        for iface in self.interfaces:
            addnames = newnames[iface] - oldnames[iface]
            delnames = oldnames[iface] - newnames[iface]
            for name in addnames:
                self.cmd(
                    "ip",
                    "link",
                    "property",
                    "add",
                    "altname",
                    name,
                    "dev",
                    iface,
                )
            for name in delnames:
                self.cmd(
                    "ip",
                    "link",
                    "property",
                    "del",
                    "altname",
                    name,
                    "dev",
                    iface,
                )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog="fc-lldp-to-altname")
    parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Do not print commands when executed",
    )
    parser.add_argument(
        "--dry-run",
        "-n",
        action="store_true",
        help="Do not change interface configuration, only print calculated commands",
    )
    parser.add_argument(
        "interfaces", metavar="IFACES", nargs="+", help="Interfaces to process"
    )

    args = parser.parse_args()
    runner = Runner(args)
    runner.run()
