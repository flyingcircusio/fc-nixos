#!/run/current-system/sw/bin/python3
"""Pressure Stall Information collector.
This script collects pressure stall information from the /proc/pressure
directory and outputs it in a format that is suitable for telegraf.
"""

import json
import re
import os

import argparse

DEVICES = ['cpu', 'memory', 'io']

PSI_PATTERN = r'(?P<extent>some|full) avg10=(?P<avg10>[0-9\.]+) avg60=(?P<avg60>[0-9\.]+) avg300=(?P<avg300>[0-9\.]+) total=(?P<total>[0-9\.]+)'

def probe(cgroup, dev):
    data = {}
    with open(f'/sys/fs/cgroup/{cgroup}/{dev}.pressure') as dev:
        for line in dev:
            entries = re.match(PSI_PATTERN, line)
            if not entries:
                continue
            entries = entries.groupdict()
            data[entries['extent']] = entries
            entries.pop('extent')
    return data

def main():
    # parse --regex argument
    parser = argparse.ArgumentParser()
    parser.add_argument('--regex', '-r', help='Regex to filter cgroups')
    args = parser.parse_args()

    if args.regex == "":
        args.regex = "^$"

    cgroup_regex = re.compile(args.regex)

    # List all cgroups
    # by recursively collecting all directories in /sys/fs/cgroup including the
    # cgroup/ itself.
    cgroups = ["/sys/fs/cgroup/"]
    for root, dirs, files in os.walk('/sys/fs/cgroup'):
        for dir in dirs:
            cgroups.append(os.path.join(root, dir))
    
    # remove /sys/fs/cgroup/ prefix from cgroups
    cgroups = [c.replace('/sys/fs/cgroup', '') for c in cgroups]

    # collect metrics for each cgroup
    metrics = {}
    for cgroup in cgroups:
        if not cgroup_regex.match(cgroup):
            continue
        # replace backslash (\) with "[backslash]" in cgroup when inserting
        # to avoid problems with telegraf's metric name escaping
        cgroup_escaped = cgroup.replace('\\', '[backslash]')
        metrics[cgroup_escaped] = {}
        for dev in DEVICES:
            metrics[cgroup_escaped][dev] = probe(cgroup, dev)
            
    # flatten result for telegraf ingestion
    result = []
    for cgroup, devices in metrics.items():
        for device, extents in devices.items():
            for extent, periods in extents.items():
                for period, value in periods.items():
                    result.append({
                        'name': 'psi_cgroup',
                        'extent': extent,
                        'period': period,
                        'cgroup': cgroup,
                        device: float(value)})

    # Telegraf exec plugin would expect the following config
    # [[inputs.exec]]
    # ...
    # data_format = "json";
    # json_name_key = "name";
    # tag_keys = ["period" "extent" "cgroup"];

    print(json.dumps(result))


if __name__ == '__main__':
    main()
