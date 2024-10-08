#!/usr/bin/env python3.4
"""Check LVM2 for input/output errors on the LV level."""

import argparse
import logging
import subprocess

import nagiosplugin

LOG = logging.getLogger("nagiosplugin")


class LVM(nagiosplugin.Resource):
    def __init__(self, lvm_cmd="lvs"):
        self.lvm_cmd = lvm_cmd

    def probe(self):
        LOG.debug('querying LVM status with "%s"', self.lvm_cmd)
        p = subprocess.Popen(
            [self.lvm_cmd],
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={"LANG": "en_US", "HOME": "/var/empty"},
        )
        out, err = p.communicate()
        output = out.decode().strip() + "\n" + err.decode().strip()
        LOG.info("full LVM status: %s", output)
        errors = 0
        for line in output.splitlines():
            if "Input/output error" in line:
                LOG.warning("%s", line)
                errors += 1
        return nagiosplugin.Metric("errors", errors, min=0)


@nagiosplugin.guarded
def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        "-l",
        "--lvs",
        metavar="CMD",
        default="lvs",
        help="command to run (default: %(default)s)",
    )
    a.add_argument(
        "-w",
        "--warning",
        metavar="RANGE",
        help="warning if error count is outside RANGE",
    )
    a.add_argument(
        "-c",
        "--critical",
        metavar="RANGE",
        help="critical if error count is outside RANGE",
    )
    a.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="increase output verbosity (up to 3 times)",
    )
    a.add_argument(
        "-t",
        "--timeout",
        default=30,
        help="abort execution after TIMEOUT seconds "
        "(default: %(default)ss)",
    )
    args = a.parse_args()
    check = nagiosplugin.Check(
        LVM(args.lvs),
        nagiosplugin.ScalarContext(
            "errors",
            args.warning,
            args.critical,
            fmt_metric="{value} errors found",
        ),
    )
    check.main(args.verbose, args.timeout)


if __name__ == "__main__":
    main()
