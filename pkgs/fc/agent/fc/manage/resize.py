"""Resizes filesystems, or reboots due to memory or Qemu changes if needed.

We expect the root partition to be partition 1 on its device, but we're
looking up the device by checking the root partition by label first.
"""

import argparse
import json

import fc.maintenance
import fc.util.dmi_memory
from fc.maintenance.system_properties import (
    request_reboot_for_cpu,
    request_reboot_for_kernel,
    request_reboot_for_memory,
    request_reboot_for_qemu,
)
from fc.util.logging import init_logging


def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        "-E",
        "--enc-path",
        default="/etc/nixos/enc.json",
        help="path to enc.json (default: %(default)s)",
    )
    a.add_argument(
        "-v",
        "--verbose",
        default=0,
        action="count",
        help="increase output verbosity",
    )
    args = a.parse_args()

    main_log_file = open("/var/log/fc-resize.log", "a")
    init_logging(args.verbose, main_log_file)

    with open(args.enc_path) as f:
        enc = json.load(f)

    with fc.maintenance.ReqManager() as rm:

        if enc["parameters"]["machine"] == "virtual":
            rm.add(request_reboot_for_memory(enc))
            rm.add(request_reboot_for_cpu(enc))
            rm.add(request_reboot_for_qemu())

        rm.add(request_reboot_for_kernel())


if __name__ == "__main__":
    main()
