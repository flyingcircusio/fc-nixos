#!/usr/bin/env python3
"""Pressure Stall Information check.

This check is to test for Pressure Stall Information, introduced in the Linux
Kernel in April 2018.

"""

import argparse
import sys
import re

PSI_PATTERN = r'(?<extent>some|full) avg10=(?<avg10>[0-9\.]+) avg60=(?<avg60>[0-9\.]+) avg300=(?<avg300>[0-9\.]+) total=(?:[0-9\.]+)'

def triple(triple_string):
    triple_list = triple_string.split(',')
    if(len(triple_list) != 3):
        print('The arguments to the warning values are triples, corresponding'
        'to the average value of 10, 60 and 300 seconds respectively')
    return tuple(triple_list)

def threshold_exceeded(threshold, value):
    for t, v in zip(threshold, value):
        if v > t:
            return True
    return False


def main():
    p = argparse.ArgumentParser()
    p.add_argument('device', choices=['cpu', 'memory', 'io'])
    p.add_argument('--some-warning', type=triple,
        help='Share of time some tasks stalling considered warning')
    p.add_argument('--some-critical', type=triple,
        help='Share of time some tasks stalling considered critical')
    p.add_argument('--full-warning', type=triple,
        help='Share of time all non-idle tasks stalling considered warning')
    p.add_argument('--full-critical', type=triple,
        help='Share of time all non-idle tasks stalling considered critical')


    args = p.parse_args()

    if (args.device == 'cpu') and (args.full_warning or args.full_critical):
        print('Pressure Stall Information for CPUs does not provide full information')

    warning = {}
    if args.some_warning:
        warning['some'] = args.some_warning
    if args.full_warning:
        warning['full'] = args.full_warning

    critical = {}
    if args.some_critical:
        critical['some'] = args.some_critical
    if args.full_warning:
        critical['full'] = args.full_critical

    actual = {}

    with open(f'/proc/pressure/{args.device}') as dev:
        for line in dev:
            entries = re.match(PSI_PATTERN, line)
            if not entries:
                continue
            entries = entries.groupdict()
            actual[entries['extent']] = (entries['avg10'], entries['avg60'], entries['avg300'])

    exit_code = 0

    if not actual:
        exit_code = max(exit_code, 1)
        print(f'WARNING - Pressure Stalling Check encountered unexpected data')

    for extent in actual:
        if threshold_exceeded(critical[extent], actual[extent]):
            exit_code = max(exit_code, 2)
            print(f'CRITICAL - {args.device} Pressure Stalling {extent} {actual[extent]} > {critical[extent]}')
        if threshold_exceeded(warning[extent], actual[extent]):
            exit_code = max(exit_code, 1)
            print(f'WARNING - {args.device} Pressure Stalling {extent} {actual[extent]} > {warning[extent]}')

    if exit_code == 0:
        print('OK - No pressure stalling issues')
    sys.exit(exit_code)


if __name__ == '__main__':
    main()
