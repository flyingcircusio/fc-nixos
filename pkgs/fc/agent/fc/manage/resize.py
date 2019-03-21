"""Resizes filesystems, or reboots due to memory or Qemu changes if needed.

We expect the root partition to be partition 1 on its device, but we're
looking up the device by checking the root partition by label first.
"""

import argparse
import fc.maintenance
import fc.maintenance.lib.reboot
import fc.manage.dmi_memory
import json
import os
import os.path as p
import re
import shutil
import subprocess


def verbose(msg):
    # may be overriden in main()
    pass


class QuotaError(RuntimeError):
    """Failed to parse XFS quota report."""
    pass


class Disk(object):
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
    FREE_SECTOR_THRESHOLD = (5 * (1024 * 1024 * 1024) / 2) / 512

    def __init__(self, dev, proj, mp):
        self.dev = dev    # block device
        self.proj = proj  # XFS project id (see /etc/projid)
        self.mp = mp      # mountpoint

    def ensure_gpt_consistency(self):
        sgdisk_out = subprocess.check_output([
            'sgdisk', '-v', self.dev]).decode()
        if 'Problem: The secondary' in sgdisk_out:
            print('resize: Ensuring GPT consistency')
            print(sgdisk_out)
            subprocess.check_call(['sgdisk', '-e', self.dev])

    r_free = re.compile(r'\s([0-9]+) free sectors')

    def free_sectors(self):
        sgdisk_out = subprocess.check_output([
            'sgdisk', '-v', self.dev]).decode()
        free = self.r_free.search(sgdisk_out)
        if not free:
            raise RuntimeError('unable to determine number of free sectors',
                               sgdisk_out)
        return(int(free.group(1)))

    def grow_partition(self):
        print('resize: Growing partition in the partition table')
        partx = subprocess.check_output(['partx', '-r', self.dev]).decode()
        first_sector = partx.splitlines()[1].split()[1]
        subprocess.check_call([
            'sgdisk', self.dev, '-d', '1',
            '-n', '1:{}:0'.format(first_sector), '-c', '1:root',
            '-t', '1:8300'])

    def resize_partition(self):
        print('resize: Growing XFS filesystem')
        partx = subprocess.check_output(['partx', '-r', self.dev]).decode()
        partition_size = partx.splitlines()[1].split()[3]   # sectors
        subprocess.check_call(['resizepart', self.dev, '1', partition_size])
        subprocess.check_call(['xfs_growfs', '/dev/disk/by-label/root'])

    def should_grow_blkdev(self):
        """Returns True if a FS grow operation is necessary."""
        self.ensure_gpt_consistency()
        free = self.free_sectors()
        return free > self.FREE_SECTOR_THRESHOLD

    def grow(self):
        """Enlarges partition and filesystem."""
        free = self.free_sectors()
        print('{} free sectors on {}, growing'.format(free, self.dev))
        self.grow_partition()
        self.resize_partition()

    def xfsq(self, cmd, ionice=False):
        """Wrapper for xfs_quota calls."""
        cmd = ['xfs_quota', '-xc', cmd, self.mp]
        if ionice:
            cmd = ['ionice', '-c3'] + cmd
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).\
            decode().strip()

    def xfs_quota_report(self):
        """Queries current XFS quota state.

        Example output:
            # xfs_quota -xc 'report -p' /
            Project quota on / (/dev/disk/by-label/root)
                                        Blocks
            Project ID       Used       Soft       Hard    Warn/Grace
            ---------- --------------------------------------------------
            rootfs       37208256   41943040   41943040     00 [--------]

        Returns pair of (used, block_hard_limit) numbers rounded to the
        next full GiB value.
        """
        report = self.xfsq('report -p')
        if not report:
            return (0, 0)
        m = re.search(r'^{}\s+(\d+)\s+\d+\s+(\d+)\s+'.format(self.proj),
                      report, re.MULTILINE)
        if not m:
            raise QuotaError('failed to parse xfs_quota output', report)
        used = m.group(1)
        blocks_hard = m.group(2)
        return (round(float(used) / 2**20), round(float(blocks_hard) / 2**20))

    def should_change_quota(self, partition, enc_disk_gb):
        """Returns True if a new quota setting is necessary."""
        if not enc_disk_gb:
            return False
        blk_size = subprocess.check_output(['lsblk', '-nbro', 'SIZE',
                                            partition]).decode().strip()
        blk_size_gb = int(round(float(blk_size) / 2**30))
        if enc_disk_gb > blk_size_gb:
            # disk grow pending
            return False
        used_gb, bhard_limit_gb = self.xfs_quota_report()
        verbose('resize: blk={} GiB, enc={} GiB, q_used={} GiB, q_limit={} GiB'
                .format(blk_size_gb, enc_disk_gb, used_gb, bhard_limit_gb))
        if enc_disk_gb == blk_size_gb and bhard_limit_gb == 0:
            # no action necessary; quota not active
            return False
        if enc_disk_gb < blk_size_gb and bhard_limit_gb != 0 and used_gb == 0:
            # something is fishy here -> reinit quota
            return True
        # logical disk size different from current quota? -> change quota
        return bhard_limit_gb != enc_disk_gb

    def set_quota(self, disk_gb):
        """Ensures only as much space as allotted can be used.

        XFS quotas are reinitialized no matter what since we don't know
        if we have been in a consistent state beforehand. This takes a
        bit longer than just setting bsoft and bhard values, but is also
        more reliable.
        """
        if not disk_gb:
            return
        print('resize: Setting XFS quota limits to {} GiB'.format(disk_gb))
        print(self.xfsq('project -s {}'.format(self.proj), ionice=True))
        print(self.xfsq('timer -p 1m'))
        print(self.xfsq('limit -p bsoft={d}g bhard={d}g {p}'.format(
            d=disk_gb, p=self.proj)))

    def remove_quota(self):
        """Removes project quota as growing filesystems don't need it."""
        print('resize: Removing XFS quota')
        used, bhard_limit = self.xfs_quota_report()
        if used > 0:
            print(self.xfsq('project -C {}'.format(self.proj), ionice=True))
        if bhard_limit > 0:
            print(self.xfsq('limit -p bsoft=0 bhard=0 {}'.format(self.proj)))


def resize_filesystems(enc):
    """Grows root filesystem if the underlying blockdevice has been resized."""
    try:
        partition = subprocess.check_output(
            ['blkid', '-L', 'root']).decode().strip()
    except subprocess.CalledProcessError as e:
        if e.returncode == 2:
            # Label was not found.
            # This happends for instance on Vagrant, where it is no problem and
            # should not be an error.
            raise SystemExit(0)

    # The partition output is '/dev/vda1'. We assume we have a single-digit
    # partition number here.
    disk = partition[:-1]
    d = Disk(disk, 'rootfs', '/')
    enc_size = int(enc['parameters'].get('disk'))
    if d.should_grow_blkdev():
        d.remove_quota()
        d.grow()
    elif d.should_change_quota(partition, enc_size):
        d.set_quota(enc_size)


def count_cores(cpuinfo='/proc/cpuinfo'):
    count = 0
    with open(cpuinfo) as f:
        for line in f.readlines():
            if line.startswith('processor'):
                count += 1
    assert count > 0
    return count


def memory_change(enc):
    """Schedules reboot if the memory size has changed."""
    enc_memory = int(enc['parameters'].get('memory', 0))
    if not enc_memory:
        return
    real_memory = fc.manage.dmi_memory.main()
    if real_memory == enc_memory:
        return
    msg = 'Reboot to change memory from {} MiB to {} MiB'.format(
        real_memory, enc_memory)
    print('resize:', msg)
    with fc.maintenance.ReqManager() as rm:
        rm.add(fc.maintenance.Request(
            fc.maintenance.lib.reboot.RebootActivity('poweroff'), 600,
            comment=msg))


def cpu_change(enc):
    """Schedules reboot if the number of cores has changed."""
    cores = int(enc['parameters'].get('cores', 0))
    if not cores:
        return
    current_cores = count_cores()
    if current_cores == cores:
        return
    msg = 'Reboot to change CPU count from {} to {}'.format(
        current_cores, cores)
    print('resize:', msg)
    with fc.maintenance.ReqManager() as rm:
        rm.add(fc.maintenance.Request(
            fc.maintenance.lib.reboot.RebootActivity('poweroff'), 600,
            comment=msg))


def check_qemu_reboot():
    """Schedules a reboot if the Qemu binary environment has changed."""
    # Update the -booted marker if necessary. We need to store the marker
    # in a place where it does not get removed after _internal_ reboots
    # of the virtual machine. However, if we got rebooted with a fresh
    # Qemu instance, we need to update it from the marker on the tmp
    # partition.
    if not p.isdir('/var/lib/qemu'):
        os.makedirs('/var/lib/qemu')
    if p.exists('/tmp/fc-data/qemu-binary-generation-booted'):
        shutil.move('/tmp/fc-data/qemu-binary-generation-booted',
                    '/var/lib/qemu/qemu-binary-generation-booted')
    # Schedule maintenance if the current marker differs from booted
    # marker.
    if not p.exists('/run/qemu-binary-generation-current'):
        return

    try:
        with open('/run/qemu-binary-generation-current', encoding='ascii') \
                as f:
            current_generation = int(f.read().strip())
    except Exception:
        # Do not perform maintenance if no current marker is there.
        return

    try:
        with open('/var/lib/qemu/qemu-binary-generation-booted',
                  encoding='ascii') as f:
            booted_generation = int(f.read().strip())
    except Exception:
        # Assume 0 as the generation marker as that is our upgrade path:
        # VMs started with an earlier version of fc.qemu will not have
        # this marker at all.
        booted_generation = 0

    if booted_generation >= current_generation:
        # We do not automatically downgrade. If we ever want that then I
        # want us to reconsider the side-effects.
        return

    msg = 'Cold restart because the Qemu binary environment has changed'
    with fc.maintenance.ReqManager() as rm:
        rm.add(fc.maintenance.Request(
            fc.maintenance.lib.reboot.RebootActivity('poweroff'), 600,
            comment=msg))


def kernel_version(kernel):
    """Guesses kernel version from /run/*-system/kernel.

    Theory of operation: A link like `/run/current-system/kernel` points
    to a bzImage like `/nix/store/abc...-linux-4.4.27/bzImage`. The
    directory also contains a `lib/modules` dir which should have the
    kernel version as sole subdir, e.g.
    `/nix/store/abc...-linux-4.4.27/lib/modules/4.4.27`. This function
    returns that version number or bails out if the assumptions laid down here
    do not hold.
    """
    bzImage = os.readlink(kernel)
    moddir = os.listdir(p.join(p.dirname(bzImage), 'lib', 'modules'))
    if len(moddir) != 1:
        raise RuntimeError('modules subdir does not contain exactly '
                           'one item', moddir)
    return moddir[0]


def check_kernel_reboot():
    """Schedules a reboot if the kernel has changed."""
    booted, current = map(kernel_version, [
        '/run/booted-system/kernel',
        '/run/current-system/kernel'])
    verbose('check_kernel: booted={}, current={}'.format(booted, current))
    if booted != current:
        print('kernel changed: scheduling reboot')
        with fc.maintenance.ReqManager() as rm:
            rm.add(fc.maintenance.Request(
                fc.maintenance.lib.reboot.RebootActivity('reboot'), 600,
                comment='Reboot to activate changed kernel '
                '({} to {})'.format(booted, current)
            ))


def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument('-E', '--enc-path', default='/etc/nixos/enc.json',
                   help='path to enc.json (default: %(default)s)')
    a.add_argument('-v', '--verbose', default=0, action='count',
                   help='increase output verbosity')
    args = a.parse_args()

    if args.verbose > 0:
        globals()['verbose'] = lambda msg: print(msg)

    check_qemu_reboot()
    check_kernel_reboot()

    if args.enc_path:
        with open(args.enc_path) as f:
            enc = json.load(f)
        resize_filesystems(enc)
        memory_change(enc)
        cpu_change(enc)


if __name__ == '__main__':
    main()
