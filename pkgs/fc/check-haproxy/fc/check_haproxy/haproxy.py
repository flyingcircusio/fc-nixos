import argparse
import datetime
import itertools
import logging
import re

import nagiosplugin
import numpy


class HAProxyLog(nagiosplugin.Resource):

    r_logline = re.compile(
        r'haproxy.*: .* \d+/\d+/\d+/\d+/(\d+) (\d\d\d) .* "\w+ (/\S+) HTTP'
    )

    def __init__(
        self, logfile, statefile, percentiles, url_filters, exclude_patterns
    ):
        self.logfile = logfile
        self.statefile = statefile
        self.percentiles = percentiles
        self.url_filters = url_filters or {None: ""}
        if exclude_patterns:
            exclude_patterns = list(
                map(lambda x: "({})".format(x), exclude_patterns)
            )
            self.r_exclude = re.compile("|".join(exclude_patterns))
        else:
            self.r_exclude = ReNull()

    def parse(self):
        """Extract tuples (t_tot, is_error, urlpath) from new log lines."""
        cookie = nagiosplugin.Cookie(self.statefile)
        records = []
        with nagiosplugin.LogTail(self.logfile, cookie) as lf:
            for line in lf:
                match = self.r_logline.search(line.decode("iso-8859-1"))
                if not match:
                    logging.debug("ignoring line: %s", line.strip())
                    continue
                if self.r_exclude.search(line.decode("iso-8859-1")):
                    logging.debug(
                        "hit exclude pattern in line: %s", line.strip()
                    )
                    continue
                t_tot, stat, url = match.groups()
                err = not (stat.startswith("2") or stat.startswith("3"))
                records.append((t_tot, err, url))
        return numpy.array(
            records,
            dtype=[
                ("t_tot", numpy.int32),
                ("err", numpy.uint16),
                ("url", "80a"),
            ],
        )

    def request_rate(self, records):
        """Create request rate metric (does not depend on url filters).

        In its current implementation, the request rate computation lies
        a little bit: we compute the rate of requests seen in the log
        file between the last check invocation and now. This must not
        necessarily equal the request rate as computed by the requests'
        timestamps.
        """

        with nagiosplugin.Cookie(self.statefile) as cookie:
            last_run = cookie.get("last_run", None)
            now = datetime.datetime.now()
            cookie["last_run"] = now.timetuple()[0:6]
            if not last_run:
                logging.info("cannot find last_run in state file")
                return nagiosplugin.Metric(
                    "rate", 0, "req/s", min=0, context="default"
                )
            last_run = datetime.datetime(*last_run)
            timedelta = max((now - last_run).total_seconds(), 1)
            return nagiosplugin.Metric(
                "rate",
                len(records) / timedelta,
                "req/s",
                min=0,
                context="default",
            )

    def filtered(self, prefix, records):
        """Return sub-list of `records` where url paths start with `prefix`."""
        prefix = prefix.encode() if isinstance(prefix, str) else prefix
        matches = [url.startswith(prefix) for url in records["url"]]
        return records.compress(matches, axis=0)

    def metrics(self, label, records):
        """Compute metrics for a set of `records`."""
        if label:
            name = lambda metric: "{} {}".format(label, metric)
        else:
            name = lambda metric: metric
        requests = len(records)
        if requests:
            for pct in self.percentiles:
                yield nagiosplugin.Metric(
                    name("t_tot%s" % pct),
                    numpy.percentile(records["t_tot"], int(pct)) / 1000,
                    "s",
                    min=0,
                    context="t_tot%s" % pct,
                )
        else:
            logging.info(
                "no requests found%s - skipping timing metrics",
                " for " + label if label else "",
            )
        errors = 100 * numpy.sum(records["err"] / requests) if requests else 0
        yield nagiosplugin.Metric(
            name("http_errors"), errors, "%", 0, 100, context="http_errors"
        )
        yield nagiosplugin.Metric(
            name("requests"), requests, min=0, context="default"
        )

    def probe(self):
        req = self.parse()
        metrics = [self.request_rate(req)]
        for label, prefix in self.url_filters.items():
            metrics += list(self.metrics(label, self.filtered(prefix, req)))
        return metrics


class HAProxyLogSummary(nagiosplugin.Summary):
    def __init__(self, percentiles):
        self.key = "t_tot%s" % percentiles[0]

    def ok(self, results):
        summary = "request rate is {}".format(results["rate"].metric.valueunit)
        if self.key in results:
            summary += " - " + str(results[self.key])
        return summary


class ReNull(object):
    def search(self, str):
        return None


def parse_args():
    argp = argparse.ArgumentParser(
        epilog="""
If one or more -f options are given, requests statistics are computed
independently for each class of requests starting with URLPREFIX. URL prefix
filtering considers only the first 80 characters of the URL path. If no -f
options are given, all requests are counted."""
    )
    argp.add_argument("logfile", metavar="LOGFILE")
    argp.add_argument("--ew", "--error-warning", metavar="RANGE", default="")
    argp.add_argument("--ec", "--error-critical", metavar="RANGE", default="")
    argp.add_argument(
        "--tw",
        "--ttot-warning",
        metavar="RANGE[,RANGE,...]",
        type=nagiosplugin.MultiArg,
        default="",
    )
    argp.add_argument(
        "--tc",
        "--ttot-critical",
        metavar="RANGE[,RANGE,...]",
        type=nagiosplugin.MultiArg,
        default="",
    )
    argp.add_argument(
        "-p",
        "--percentiles",
        metavar="N,N,...",
        default="50,95",
        help="check Nth percentiles of total time " "(default: %(default)s)",
    )
    argp.add_argument(
        "-v",
        "--verbose",
        action="count",
        default=0,
        help="increase output verbosity (use up to 3 times)",
    )
    argp.add_argument(
        "-t",
        "--timeout",
        default=30,
        help="abort execution after TIMEOUT seconds",
    )
    argp.add_argument(
        "-s",
        "--state-file",
        default="check_haproxy_log.state",
        help="cookie file to save last log file position "
        '(default: "%(default)s")',
    )
    argp.add_argument(
        "-f",
        "--filter",
        metavar="LABEL:URLPREFIX",
        action="append",
        default=[],
        help="filter URLs into labeled buckets and compute "
        "statistics for each bucket",
    )
    argp.add_argument(
        "-e",
        "--exclude",
        metavar="PATTERN",
        action="append",
        default=[],
        help="exclude log lines matching given pattern",
    )
    return argp.parse_args()


@nagiosplugin.guarded
def main():
    args = parse_args()
    percentiles = args.percentiles.split(",")
    url_filters = {}
    exclude_patterns = []
    for expr in args.filter:
        label, urlprefix = expr.split(":", 1)
        url_filters[label] = urlprefix
    for pattern in args.exclude:
        exclude_patterns.append(pattern)
    check = nagiosplugin.Check(
        HAProxyLog(
            args.logfile,
            args.state_file,
            percentiles,
            url_filters,
            exclude_patterns,
        ),
        nagiosplugin.ScalarContext("http_errors", args.ew, args.ec),
        HAProxyLogSummary(percentiles),
    )
    for pct, i in zip(percentiles, itertools.count()):
        check.add(
            nagiosplugin.ScalarContext(
                "t_tot%s" % pct,
                args.tw[i],
                args.tc[i],
                "total req time (%s.pct) is {valueunit}" % pct,
            )
        )
    check.main(args.verbose, args.timeout)


if __name__ == "__main__":
    main()
