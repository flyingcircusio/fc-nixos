#!/run/current-system/sw/bin/python3
"""Pressure Stall Information collector.
This script collects pressure stall information from the /proc/pressure
directory and outputs it in a format that is suitable for telegraf.
"""

import json
import re

DEVICES = ["cpu", "memory", "io"]

PSI_PATTERN = r"(?P<extent>some|full) avg10=(?P<avg10>[0-9\.]+) avg60=(?P<avg60>[0-9\.]+) avg300=(?P<avg300>[0-9\.]+) total=(?P<total>[0-9\.]+)"


def probe_device(dev):
    data = {}
    with open(f"/proc/pressure/{dev}") as dev:
        for line in dev:
            entries = re.match(PSI_PATTERN, line)
            if not entries:
                continue
            entries = entries.groupdict()
            data[entries["extent"]] = entries
            entries.pop("extent")
    return data


def probe():
    devices = {}
    for dev in DEVICES:
        devices[dev] = probe_device(dev)
    return devices


def main():
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

    data = probe()

    result = []

    for device, extents in data.items():
        for extent, periods in extents.items():
            for period, value in periods.items():
                result.append(
                    {
                        "name": "psi",
                        "extent": extent,
                        "period": period,
                        device: float(value),
                    }
                )

    print(json.dumps(result))


if __name__ == "__main__":
    main()
