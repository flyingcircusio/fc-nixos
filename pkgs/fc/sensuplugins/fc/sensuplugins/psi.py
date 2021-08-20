#!/usr/bin/env python3
"""Pressure Stall Information check.

This check is to test for Pressure Stall Information, introduced in the Linux
Kernel in April 2018.

"""

import argparse
import re
import sys

DEVICES = ['cpu', 'memory', 'io']

PSI_PATTERN = r'(?P<extent>some|full) avg10=(?P<avg10>[0-9\.]+) avg60=(?P<avg60>[0-9\.]+) avg300=(?P<avg300>[0-9\.]+) total=(?P<total>:[0-9\.]+)'


def triple(triple_string):
    triple_list = triple_string.split(',')
    if (len(triple_list) != 3):
        print('The arguments to the warning values are triples, corresponding'
              'to the average value of 10, 60 and 300 seconds respectively')
    return tuple(triple_list)


def threshold_exceeded(threshold, value):
    for t, v in zip(threshold, value):
        if v > t:
            return True
    return False


def probe_device(dev, use_dict=False):
    data = {}
    with open(f'/proc/pressure/{dev}') as dev:
        for line in dev:
            entries = re.match(PSI_PATTERN, line)
            if not entries:
                continue
            entries = entries.groupdict()
            if not use_dict:
                data[entries['extent']] = (entries['avg10'], entries['avg60'],
                                           entries['avg300'])
            else:
                data[entries['extent']] = entries
    return data


def probe(use_dict=False):
    devices = {}
    for dev in DEVICES:
        devices[dev] = probe_device(dev, use_dict)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('device', choices=DEVICES)
    p.add_argument(
        '--some-warning',
        type=triple,
        help='Share of time some tasks stalling considered warning')
    p.add_argument(
        '--some-critical',
        type=triple,
        help='Share of time some tasks stalling considered critical')
    p.add_argument(
        '--full-warning',
        type=triple,
        help='Share of time all non-idle tasks stalling considered warning')
    p.add_argument(
        '--full-critical',
        type=triple,
        help='Share of time all non-idle tasks stalling considered critical')

    args = p.parse_args()

    if (args.device == 'cpu') and (args.full_warning or args.full_critical):
        print(
            'Pressure Stall Information for CPUs does not provide full information'
        )

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

    data = probe()
    actual = data[args.device]
    exit_code = 0

    if not actual:
        exit_code = max(exit_code, 1)
        print(f'WARNING - Pressure Stalling Check encountered unexpected data')

    for extent in actual:
        if threshold_exceeded(critical[extent], actual[extent]):
            exit_code = max(exit_code, 2)
            print(
                f'CRITICAL - {args.device} Pressure Stalling {extent} {actual[extent]} > {critical[extent]}'
            )
        if threshold_exceeded(warning[extent], actual[extent]):
            exit_code = max(exit_code, 1)
            print(
                f'WARNING - {args.device} Pressure Stalling {extent} {actual[extent]} > {warning[extent]}'
            )

    if exit_code == 0:
        print('OK - No pressure stalling issues')
    sys.exit(exit_code)


if __name__ == '__main__':
    main()


def telegraf():
    # Output to be used by telegraf's exec plugin.
    #
    # Expected config for telegraf's json parser:
    # [[inputs.exec]]
    # ...
    # data_format = "json";
    # json_name_key = "name";
    # tag_keys = ["period" "extent"];
    #
    # Output format:
    # [{"name": "psi", "extent": "full", "period": "avg10", "io": 33.7},
    #  {"name": "psi", "extent": "full", "period": "avg60", "io": 20.7},
    #  {"name": "psi", "extent": "full", "period": "avg300", "io": 15.7},
    #  {"name": "psi", "extent": "full", "period": "total", "io": 15.7},
    #  {"name": "psi", "extent": "some", "period": "avg10", "io": 33.7},
    #  {"name": "psi", "extent": "some", "period": "avg60", "io": 20.7},
    #  {"name": "psi", "extent": "some", "period": "avg300", "io": 15.7},
    #  {"name": "psi", "extent": "some", "period": "total", "io": 15.7},
    #  {"name": "psi", "extent": "full", "period": "avg10", "memory": 33.7},
    #  {"name": "psi", "extent": "full", "period": "avg60", "memory": 20.7},
    #  {"name": "psi", "extent": "full", "period": "avg300", "memory": 15.7},
    #  {"name": "psi", "extent": "full", "period": "total", "memory": 15.7},
    #  {"name": "psi", "extent": "some", "period": "avg10", "memory": 33.7},
    #  {"name": "psi", "extent": "some", "period": "avg60", "memory": 20.7},
    #  {"name": "psi", "extent": "some", "period": "avg300", "memory": 15.7},
    #  {"name": "psi", "extent": "some", "period": "total", "memory": 15.7}]

    data = probe(include_total=True)

    result = []

    for device, extents in data.items():
        for extent, periods in extents.items():
            for period, value in periods.items():
                result.append({
                    'name': 'psi',
                    'extent': extent,
                    'period': period,
                    device: value})

    print(json.dumps(result))
