"""Check whether paths are writable and responsive.

Takes a list of filenames and verifies (destructively) that they can be written
and flushed to disk.

"""

import argparse
import logging
import nagiosplugin
import os
import sys


_log = logging.getLogger('nagiosplugin')


class Path(nagiosplugin.Resource):
    """Does the actual work of writing to a path."""

    def __init__(self, path):
        self.path = path

    def probe(self):
        _log.debug('probe: %r', self.path)
        with open(self.path, 'w') as f:
            f.write('asdf')
            f.flush()
            os.fsync(f)
        return nagiosplugin.Metric(self.path, True, context='null')


class PathSummary(nagiosplugin.Summary):

    def ok(self, results):
        msg = []
        for r in results:
            msg.append('{}: {}'.format(r.metric.name, r.metric.valueunit))
        return ', '.join(msg)

    def problem(self, results):
        msg = []
        for r in results.most_significant:
            msg.append('{}: {}'.format(r.metric.name, r.metric.valueunit))
        return ', '.join(msg)


@nagiosplugin.guarded
def main():
    a = argparse.ArgumentParser(description=__doc__, epilog="""\
Arguments for individually configured filesystems:
MOUNTPOINT[,WARN[,CRIT[,DISKSIZE[,NORMSIZE[,MAGIC]]]]].  WARN,CRIT - alert
ranges; DISKSIZE - overrides device size; NORMSIZE - individual reference value
for magic calculation; MAGIC - individual magic factor for dampening
calculation.
""")
    a.add_argument('-v', '--verbose', action='count', default=0,
                   help='increase verbosity')

    a.add_argument('-t', '--timeout', metavar='N', default=30, type=int,
                   help='abort check execution after N seconds')
    a.add_argument('paths', type=str, nargs='+', help='paths to check')

    args = a.parse_args()
    check = nagiosplugin.Check(PathSummary())
    for path in args.paths:
        check.add(Path(path))
    check.main(args.verbose, args.timeout)

    targets = sys.argv[1:]

    for target in targets:
        print("Writing {}".format(target))
