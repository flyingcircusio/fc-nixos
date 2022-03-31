import re
import subprocess

import structlog

log = structlog.get_logger()


class Disk:
    """Resizes root filesystem.

    This part of the resizing code does not know or care about the
    intended size of the disk. It only checks what size the disk has and
    then aligns the partition table and filesystems appropriately.

    The actual sizing of the disk is delegated to the KVM host
    management utilities and happens independently.

    Some of the tools need partition numbers, though. We hardcoded that
    for now.
    """

    # 5G disk size granularity -> 2.5G sampling -> 512 byte sectors
    FREE_SECTOR_THRESHOLD = int((5 * (1024 * 1024 * 1024) / 2) / 512)

    def __init__(self, dev, mp):
        self.dev = dev  # block device
        self.mp = mp  # mountpoint

    def ensure_gpt_consistency(self):
        sgdisk_out = subprocess.check_output(
            ["sgdisk", "-v", self.dev]
        ).decode()
        if "Problem: The secondary" in sgdisk_out:
            log.warn("resize-ensure-gpt-consistency", out=sgdisk_out)
            subprocess.check_call(["sgdisk", "-e", self.dev])

    r_free = re.compile(r"\s([0-9]+) free sectors")

    def free_sectors(self):
        sgdisk_out = subprocess.check_output(
            ["sgdisk", "-v", self.dev]
        ).decode()
        free = self.r_free.search(sgdisk_out)
        if not free:
            raise RuntimeError(
                "unable to determine number of free sectors", sgdisk_out
            )
        return int(free.group(1))

    def grow_partition(self):
        log.info(
            "grow-partition",
            _replace_msg="Growing partition in the partition table",
            dev=self.dev,
        )
        partx = subprocess.check_output(["partx", "-r", self.dev]).decode()
        first_sector = partx.splitlines()[1].split()[1]
        subprocess.check_call(
            [
                "sgdisk",
                self.dev,
                "-d",
                "1",
                "-n",
                "1:{}:0".format(first_sector),
                "-c",
                "1:root",
                "-t",
                "1:8300",
            ]
        )

    def grow_filesystem(self):
        log.info("resize-partition", _replace_msg="Growing XFS filesystem")
        partx = subprocess.check_output(["partx", "-r", self.dev]).decode()
        partition_size = partx.splitlines()[1].split()[3]  # sectors
        # Tell kernel about the new size of the partition.
        subprocess.check_call(["resizepart", self.dev, "1", partition_size])
        # Grow XFS filesystem to the partition size.
        subprocess.check_call(["xfs_growfs", "/"])

    def should_grow(self):
        """Returns True if a FS grow operation is necessary."""
        self.ensure_gpt_consistency()
        free = self.free_sectors()
        threshold_reached = free > self.FREE_SECTOR_THRESHOLD
        log.debug(
            "resize-disk-should-grow",
            free=free,
            threshold=self.FREE_SECTOR_THRESHOLD,
            threshold_reached=threshold_reached,
        )
        return threshold_reached

    def grow(self):
        """Enlarges partition and filesystem."""
        self.grow_partition()
        self.grow_filesystem()


def resize():
    """Grows root filesystem if the underlying blockdevice has been resized."""
    log.debug("resize-start")
    try:
        partition = (
            subprocess.check_output(["blkid", "-L", "root"]).decode().strip()
        )
    except subprocess.CalledProcessError as e:
        if e.returncode == 2:
            # Label was not found. This happens for instance in containers,
            # where it is no problem and should not be an error.
            log.warn("resize-root-label-not-found")
            return
        else:
            raise

    # The partition output is '/dev/vda1'. We assume we have a single-digit
    # partition number here.
    disk = partition[:-1]
    d = Disk(disk, "/")
    if d.should_grow():
        d.grow()
