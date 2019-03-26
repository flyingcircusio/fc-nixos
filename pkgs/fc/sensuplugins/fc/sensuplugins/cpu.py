#!/usr/bin/env python3
"""CPU % check.

The main feature of this check is:

- build an average over a period for all CPUs
- allow selecting specific metrics to match

Could be / should be adapted to a plugin library at some point.
"""

import argparse
import logging
import os
import subprocess
import sys

_log = logging.getLogger('nagiosplugin')


def get_data(mpstat):
    output = subprocess.check_output([
        mpstat, '5', '6'],
        env={'LANG': 'en_US.utf8', 'PATH': os.environ['PATH']}
    ).decode('ascii')
    headings = []
    fields = []
    for line in output.splitlines():
        line = line.split()
        if 'CPU' in line and '%usr' in line:
            # This is the summary line. This tells us the headings.
            headings = line[line.index('CPU') + 1:]
        if 'Average:' in line:
            fields = line[2:]

    return dict(zip(headings, fields))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--mpstat', metavar='PATH', help='mpstat binary',
                   default='mpstat')
    args = p.parse_args()
    data = get_data(args.mpstat)
    if '%steal' not in data:
        print('UNKNOWN - did not find %steal data')
        sys.exit(3)
    steal = float(data.get('%steal'))
    if steal >= 15:
        print('CRITICAL - steal {}% >= 15%'.format(steal))
        sys.exit(2)
    if steal >= 10:
        print('WARNING - steal {}% >= 10%'.format(steal))
        sys.exit(1)
    print('OK - steal {}%'.format(steal))


if __name__ == '__main__':
    main()
