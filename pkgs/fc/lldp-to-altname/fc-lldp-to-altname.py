#!/usr/bin/env python3

import argparse
import json
import socket
import subprocess
import sys


class Runner(object):
    ALTNAME_PREFIX = "ul-port-"

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
                sys.exit(1)
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
                sys.exit(1)
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
                if "altnames" in datum:
                    names = [
                        name
                        for name in datum["altnames"]
                        if name.startswith(self.ALTNAME_PREFIX)
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
                data = data["interface"][iface]["chassis"]
                lldpnames[iface].update(data.keys())

        # ensure that peer names learned from lldp are globally unique
        # across all interfaces.
        for this_index, this_iface in enumerate(self.interfaces):
            for this_name in lldpnames[this_iface]:
                this_count = 0
                for next_iface in self.interfaces[this_index + 1 :]:
                    next_names = lldpnames[next_iface]
                    if this_name in next_names:
                        next_name = f"{this_name}-{this_count}"
                        next_names.remove(this_name)
                        next_names.add(next_name)
                        this_count += 1

        newnames = dict()
        for iface in self.interfaces:
            newnames[iface] = set(
                map(lambda n: self.ALTNAME_PREFIX + n, lldpnames[iface])
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
