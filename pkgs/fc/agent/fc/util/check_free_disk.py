"""
Check if there's enough disk space to safely install a system update.
"""

import os
import subprocess
import sys
from pathlib import Path


def system_closure_size(system_path: Path):
    args = ["nix", "path-info", "-S", system_path]
    try:
        result = subprocess.run(
            args,
            check=True,
            capture_output=True,
            text=True,
        )
        size = result.stdout.split()[1]

    except subprocess.CalledProcessError:
        sys.exit(128)

    return int(size)


def get_free_store_disk_space():
    """
    Returns free disk space for the device where /nix/store resides, in bytes.
    """
    statvfs = os.statvfs("/nix/store")
    return statvfs.f_frsize * statvfs.f_bavail


free_disk_gib = get_free_store_disk_space() / 1024**3
disk_keep_free = 5.0
size_gib = system_closure_size(Path("/run/current-system")) / 1024**3
free_space_error_thresh = size_gib + disk_keep_free
free_space_warning_thresh = size_gib * 2 + disk_keep_free

if free_disk_gib < free_space_error_thresh:
    print(
        "CRITICAL: Not enough free disk space to build a new system. "
        f"Free: {free_disk_gib:.1f} GiB. "
        f"Required: {free_space_error_thresh:.1f} GiB "
        f"({size_gib:.1f} system size + {disk_keep_free:.1f}). "
        "Automated updates are suspended until more space is available."
    )
    sys.exit(2)

elif free_disk_gib < free_space_warning_thresh:
    print(
        f"WARNING: Free disk space is getting low. "
        f"Free: {free_disk_gib:.1f} GiB. "
        f"Required: {free_space_error_thresh:.1f} GiB "
        f"({size_gib:.1f} system size + {disk_keep_free:.1f}). "
        "Building a new system could fail if more disk space is used."
    )
    sys.exit(1)


nixos_version_path = Path("/run/current-system/nixos-version")
system_version = nixos_version_path.read_text()

print(
    f"System size: {size_gib:.1f} GiB. "
    f"Free: {free_disk_gib:.1f} GiB. "
    f"System version: {system_version}"
)
