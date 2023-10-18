"""Check the size of the journal file.

Files which are smaller than 500 bytes are considered to be defect.
"""

import argparse
import logging
import os.path
from glob import glob

from nagiosplugin import (
    Check,
    Context,
    Critical,
    Metric,
    Ok,
    Range,
    Resource,
    Result,
    Summary,
    guarded,
)

_log = logging.getLogger("nagiosplugin")


class JournalFile(Resource):
    def __init__(self, res="/var/log/journal/*/*.journal"):
        self.journal_files = res

    def probe(self):
        for file in glob(self.journal_files):
            size = os.path.getsize(file)
            yield Metric(file, size, "B", min=0, context="critical")


class JournalFileSummary(Summary):
    def ok(self, results):
        return "{} journal files".format(len(results))

    def problem(self, results):
        msg = []
        for r in results.most_significant:
            msg.append("{}: {}".format(r.metric.name, r.metric.valueunit))
        return ", ".join(msg)


class SimpleContext(Context):
    def __init__(
        self,
        name,
        critical=None,
        fmt_metric="{name} is {valueunit}",
        result_cls=Result,
    ):
        super(SimpleContext, self).__init__(name, fmt_metric, result_cls)
        self.critical = Range(critical)

    def evaluate(self, metric, resource):
        if not self.critical.match(metric.value):
            return self.result_cls(Critical, self.critical.violation, metric)
        else:
            return self.result_cls(Ok, None, metric)


@guarded
def main():
    a = argparse.ArgumentParser()
    a.add_argument(
        "-c",
        "--critical",
        metavar="RANGE",
        default="500:",
        help="return critical if file is outside RANGE",
    )

    args = a.parse_args()
    check = Check(
        JournalFile(),
        SimpleContext("critical", critical=args.critical),
        JournalFileSummary(),
    )
    check.main()


if __name__ == "__main__":
    main()
