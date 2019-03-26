#!/usr/bin/env python3
"""Swap usage check.

The main feature of this check is to test for absolute swap usage, which the
default check_swap of Nagios can't do.

"""

import argparse
import psutil
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--critical', '-c', type=int, default=2048,
                   help='Swap usage in MiB considered critical')
    p.add_argument('--warning', '-w', type=int, default=1024,
                   help='Swap usage in MiB considered warning')

    args = p.parse_args()

    swap = psutil.swap_memory().used
    swap = int(swap / (1024 * 1024))  # convert to MiB
    if swap >= args.critical:
        print('CRITICAL - swap {} MiB >= {} MiB'.format(swap, args.critical))
        sys.exit(2)
    if swap >= args.warning:
        print('WARNING - swap {} MiB >= {} MiB'.format(swap, args.warning))
        sys.exit(1)
    print('OK - swap {} MiB'.format(swap))


if __name__ == '__main__':
    main()
