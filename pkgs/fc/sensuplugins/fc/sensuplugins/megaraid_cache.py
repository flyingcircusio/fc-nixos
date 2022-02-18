"""Compare current cache policy to default cache policy (CP).

Differences between the default CP and the current CP are usually a sign
for trouble. The most common cause is that the battery's capacity has
run down and the controller does not trust its BBU anymore.

Also check the BBU explicitly for the "battery replacement required"
flag. If this flag is set, return CRITICAL unconditionally.
"""

import argparse
import collections
import logging
import os
import re
import subprocess

import nagiosplugin

_log = logging.getLogger("nagiosplugin")


class LdInfo(object):

    r_virtual_disk = re.compile(r"^Virtual Disk: (\d+)")

    @staticmethod
    def _query_adapter(command):
        stdout = subprocess.check_output([command], shell=True).decode()
        return stdout.splitlines()

    @classmethod
    def from_megacli(cls, command):
        disks = collections.defaultdict(list)
        current_disk = None
        for line in cls._query_adapter(command):
            m = cls.r_virtual_disk.match(line)
            if m:
                current_disk = int(m.group(1))
            if current_disk is not None:
                disks[current_disk].append(line)
        for diskid, config in disks.items():
            yield cls(diskid, config)

    def __init__(self, diskid, config):
        self.diskid = diskid
        self.config = config


class MegaRAIDCache(nagiosplugin.Resource):
    def __init__(self, ld):
        self.ld = ld
        self.default = set()
        self.current = set()

    @property
    def diskid(self):
        return self.ld.diskid

    def parse_items(self, policy):
        return [i.strip() for i in policy.split(",")]

    r_default = re.compile(r"Default Cache Policy: (.*)")
    r_current = re.compile(r"Current Cache Policy: (.*)")

    def parse(self):
        default_cache = current_cache = []
        for line in self.ld.config:
            _log.debug("VD {}: " + line, self.ld.diskid)
            m = self.r_default.match(line)
            if m:
                default_cache = self.parse_items(m.group(1))
            m = self.r_current.match(line)
            if m:
                current_cache = self.parse_items(m.group(1))
        return set(default_cache), set(current_cache)

    def probe(self):
        self.default, self.current = self.parse()
        differences = self.default ^ self.current
        _log.info("VD %d default CP: %s", self.diskid, ", ".join(self.default))
        _log.info("VD %d current CP: %s", self.diskid, ", ".join(self.current))
        yield nagiosplugin.Metric(
            "vd{}_policy_diff".format(self.diskid),
            len(differences) // 2,
            min=0,
            context="policy_diff",
        )

    def __repr__(self):
        return "{}({}, {})".format(
            self.__class__.__name__, self.diskid, self.ld.config
        )

    @property
    def missing(self):
        return " ".join(self.default - self.current)

    @property
    def unexpected(self):
        return " ".join(self.current - self.default)


class FailureCount(nagiosplugin.Resource):
    def __init__(self, ld):
        self.ld = ld
        self.errors = 0
        self.predictive = 0

    r_error_count = re.compile(r"Error Count: (\d+)")
    r_predictive_failure_count = re.compile(r"Predictive Failure Count: (\d+)")

    @property
    def vd(self):
        return self.ld.diskid

    def probe(self):
        for line in self.ld.config:
            m = self.r_error_count.search(line)
            if m:
                _log.debug("VD %d: %s", self.vd, line.strip())
                self.errors += int(m.group(1))
                continue
            m = self.r_predictive_failure_count.search(line)
            if m:
                _log.debug("VD %d: %s", self.vd, line.strip())
                self.predictive += int(m.group(1))
                continue
        return [
            nagiosplugin.Metric(
                "vd{}_error_count".format(self.vd),
                self.errors,
                min=0,
                context="error_count",
            ),
            nagiosplugin.Metric(
                "vd{}_predictive_failure".format(self.vd),
                self.predictive,
                min=0,
                context="error_count",
            ),
        ]


class BatteryReplace(nagiosplugin.Resource):
    """Check BBU battery replacement status."""

    def __init__(self, command):
        self.command = command

    def probe(self):
        _log.debug('querying battery status with "%s"', self.command)
        try:
            stdout = subprocess.check_output(
                [self.command], shell=True
            ).decode()
        except subprocess.CalledProcessError as e:
            if e.returncode == 34:
                # adapter without bbu
                return [nagiosplugin.Metric("battery_replacement", "no")]
            raise RuntimeError(
                "failed to query BBU status", e.output, e.returncode
            )
        if not "BBU status for Adapter" in stdout:
            # There is no adapter (with BBU) here at all. Nothing to report
            return [nagiosplugin.Metric("battery_replacement", "none")]
        _log.info("battery status: %s", stdout)
        for line in stdout.splitlines():
            try:
                key, val = (w.strip().lower() for w in line.split(":", 1))
            except ValueError:
                continue
            if key == "battery replacement required":
                return [nagiosplugin.Metric("battery_replacement", val)]
            if key == "battery state" and val == "unknown":
                return [nagiosplugin.Metric("battery_replacement", "unknown")]
        raise RuntimeError("could not find battery replacement flag in output")


class BatteryReplaceContext(nagiosplugin.Context):
    def evaluate(self, metric, resource):
        if metric.value == "yes":
            return nagiosplugin.Result(
                nagiosplugin.Critical,
                "{}: {}".format(metric.name, metric.value),
                metric,
            )
        if metric.value == "unknown":
            return nagiosplugin.Result(
                nagiosplugin.Unknown,
                "could not find specific battery status in output",
            )
        return nagiosplugin.Result(nagiosplugin.Ok)


class MegaRAIDSummary(nagiosplugin.Summary):
    def ok(self, results):
        return "all VDs are working as expected"

    def problem(self, results):
        msg = []
        for result in results.most_significant:
            r = result.resource
            if isinstance(r, MegaRAIDCache):
                msg.append(
                    "VD {}: missing {}, unexpected {}".format(
                        r.diskid, r.missing, r.unexpected
                    )
                )
            elif isinstance(r, BatteryReplace):
                msg.append("battery replacement required")
            elif isinstance(r, FailureCount):
                if r.errors:
                    msg.append("media errors on VD {}".format(r.vd))
                else:
                    msg.append("predictive failures on VD {}".format(r.vd))
        return "; ".join(msg)


def parse_args():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        "-e",
        "--execute",
        metavar="COMMAND",
        default="MegaCli -LdPdInfo -aALL",
        help="run this command to obtain the controller's "
        'status (default: "%(default)s")',
    )
    a.add_argument(
        "-b",
        "--bbu-exec",
        metavar="COMMAND",
        default="MegaCli -AdpBbuCmd -GetBbuStatus -aALL",
        help="run this command to obtain the BBU's status "
        '(default: "%(default)s")',
    )
    a.add_argument(
        "-w",
        "--warning",
        metavar="RANGE",
        default="0",
        help="warning if differing CP properties are out of range "
        "(default: %(default)s)",
    )
    a.add_argument(
        "-c",
        "--critical",
        metavar="RANGE",
        default="1",
        help="critical if differing CP properties are out of range "
        "(default: %(default)s)",
    )
    a.add_argument(
        "-W",
        "--errors-warning",
        metavar="RANGE",
        default="0",
        help="warning if error count is outside RANGE "
        "(default: %(default)s)",
    )
    a.add_argument(
        "-C",
        "--errors-critical",
        metavar="RANGE",
        default="2",
        help="critical if error count is outside RANGE "
        "(default: %(default)s)",
    )
    a.add_argument(
        "-f",
        "--predictive-failure-warn",
        metavar="RANGE",
        default="1",
        help="warning if predictive failure count "
        "is outside RANGE (default: %(default)s)",
    )
    a.add_argument(
        "-F",
        "--predictive-failure-crit",
        metavar="RANGE",
        default="10",
        help="critical if predictive failure count "
        "is outside RANGE (default: %(default)s)",
    )
    a.add_argument(
        "-r",
        "--remove",
        default=False,
        action="store_true",
        help="remove MegaSAS.log after tool invocation",
    )
    a.add_argument(
        "-t",
        "--timeout",
        default=20,
        help="abort execution after " "TIMEOUT seconds (default: %(default)s)",
    )
    a.add_argument(
        "-v", "--verbose", default=0, action="count", help="increase verbosity"
    )
    return a.parse_args()


@nagiosplugin.guarded
def main():
    args = parse_args()
    check = nagiosplugin.Check(
        nagiosplugin.ScalarContext("policy_diff", args.warning, args.critical),
        nagiosplugin.ScalarContext(
            "error_count", args.errors_warning, args.errors_critical
        ),
        nagiosplugin.ScalarContext(
            "predictive_failure",
            args.predictive_failure_warn,
            args.predictive_failure_crit,
        ),
        BatteryReplaceContext("battery_replacement"),
        MegaRAIDSummary(),
    )
    for ldinfo in LdInfo.from_megacli(args.execute):
        check.add(MegaRAIDCache(ldinfo))
        check.add(FailureCount(ldinfo))
    check.add(BatteryReplace(args.bbu_exec))
    try:
        check.main(args.verbose, args.timeout)
    finally:
        if args.remove:
            try:
                os.unlink("MegaSAS.log")
            except OSError:
                pass


if __name__ == "__main__":
    main()
