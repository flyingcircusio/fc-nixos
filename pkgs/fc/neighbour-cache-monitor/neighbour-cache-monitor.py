#!/usr/bin/env python3

import argparse
import json
import subprocess
import sys

CACHE_TYPES = {
    "ipv4": "arp_cache",
    "ipv6": "ndisc_cache",
}


def warning(msg):
    print(f"WARN - {msg}")
    sys.exit(1)


def critical(msg):
    print(f"CRITICAL - {msg}")
    sys.exit(2)


def ok(msg):
    print(f"OK - {msg}")
    sys.exit(0)


def read_cache_stats(cache_type):
    # XXX: lnstat unconditionally returns exit code 1, even on
    # success.
    proc = subprocess.run(
        [
            "lnstat",
            "-f",
            cache_type,
            "-j",
            "-c1",
        ],
        capture_output=True,
    )
    return json.loads(proc.stdout.decode("utf-8"))


def read_table_threshold(family):
    data = subprocess.check_output(
        ["sysctl", "-n", f"net.{family}.neigh.default.gc_thresh3"]
    )
    data = data.strip()
    return int(data)


def telegraf(args):
    # pass through lnstat output to telegraf verbatim, annotated with
    # address family
    metrics = []
    for family, cache_type in CACHE_TYPES.items():
        data = read_cache_stats(cache_type)
        data["family"] = family
        metrics.append(data)
    print(json.dumps(metrics))


def sensu(args):
    entries = {}
    overflows = {}
    thresholds = {}
    for family, cache_type in CACHE_TYPES.items():
        data = read_cache_stats(cache_type)
        overflows[family] = data["table_fulls"]
        entries[family] = data["entries"]

        thresholds[family] = read_table_threshold(family)

    with open(args.state_file, "a+b") as fh:
        fh.seek(0)
        data = fh.read()

        # only attempt to decode json if the file is non-empty. file
        # is empty on first creation.
        state = None
        if len(data) > 0:
            try:
                state = json.loads(data.decode("utf-8"))
            except json.JSONDecodeError:
                pass

        fh.seek(0)
        fh.truncate()
        fh.write(json.dumps(overflows).encode("utf-8"))

    # perform checks family-wise in descending order of urgency

    if state is not None:
        for family in CACHE_TYPES.keys():
            if overflows[family] > state[family]:
                critical(f"{family} neighbour table overflows detected!")

    for family in CACHE_TYPES.keys():
        if (
            entries[family]
            > (thresholds[family] * args.critical_threshold) // 100
        ):
            critical(
                f"{family} neighbour table exceeded {args.critical_threshold}% capacity"
            )

    for family in CACHE_TYPES.keys():
        if entries[family] > (thresholds[family] * args.warn_threshold) // 100:
            warning(
                f"{family} neighbour table exceeded {args.warn_threshold}% capacity"
            )

    ok("neighbour tables within capacity limits")


def main():
    parser = argparse.ArgumentParser(prog="neighbour-cache-monitor")
    subparsers = parser.add_subparsers(required=True, dest="command")

    telegraf_parser = subparsers.add_parser(
        "telegraf-metrics", help="Generate Telegraf-compatible metrics"
    )
    telegraf_parser.set_defaults(func=telegraf)

    sensu_parser = subparsers.add_parser(
        "sensu-check",
        help="Sensu-compatible check which monitors neighbour table size and overflow state",
    )
    sensu_parser.set_defaults(func=sensu)

    sensu_parser.add_argument(
        "-s",
        "--state-file",
        metavar="FILE",
        required=True,
        help="Table overflow statistics state file",
    )
    sensu_parser.add_argument(
        "-w",
        "--warn-threshold",
        metavar="WARN",
        type=int,
        default=30,
        help="Issue warning when table entry count greater than WARN % of gc_thresh3",
    )
    sensu_parser.add_argument(
        "-c",
        "--critical-threshold",
        metavar="CRIT",
        type=int,
        default=50,
        help="Issue critical when table entry count greater than CRIT % of gc_thresh3",
    )

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
