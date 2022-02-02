#!/usr/bin/env python3
"""Apply kernel ioscheduler and LSI settings based on device heuristics."""

import argparse
import logging
import logging.handlers
import os
import os.path as p
import re
import subprocess
import sys
import time
from glob import glob

_log = logging.getLogger()


class BlockDev:

    # set by update_from_ldpd
    lsi_ld = None
    multidisk = False

    def __init__(self, kernel, vendor, model='', ssd=False):
        self.kernel = kernel
        self.vendor = vendor.upper()
        self.model = model.upper()
        self.ssd = ssd
        self.lsi = vendor in ['LSI', 'AVAGO', 'DELL']

    def __str__(self):
        return '{} product="{}/{}" LD={} multi={} ssd={}'.format(
            self.kernel, self.vendor, self.model, self.ld_repr, self.multidisk,
            self.ssd)

    @property
    def ld_repr(self):
        """LD number if any, or "*" if unknown yet but controller present"""
        if not self.lsi:
            return '-'
        if self.lsi and self.lsi_ld is None:
            return '*'
        return str(self.lsi_ld)

    def set_sysfs(self, relpath, setting):
        path = p.join('/sys/block', self.kernel, relpath)
        _log.debug('%s = %s', path, setting)
        try:
            with open(path, 'w') as f:
                f.write(setting)
        except Exception:
            import pdb
            pdb.set_trace()

    def update_from_ldpd(self, controller_info):
        self.lsi_ld = controller_info.ld
        self.ssd = controller_info.is_ssd
        self.multidisk = controller_info.is_multi

    def scheduler_available(self, which):
        with open(p.join('/sys/block', self.kernel, 'queue/scheduler')) as f:
            return which in f.read()


class MegaCliUpdate:

    def __init__(self, megacli):
        self.megacli = megacli

    def _ldsetprop(self, dev, prop):
        cmdline = [
            self.megacli, '-LDSetProp', prop, '-L{}'.format(dev.lsi_ld), '-a0']
        _log.debug('exec: %s', ' '.join(cmdline))
        p = subprocess.Popen(
            cmdline, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if p.wait() != 0:
            _log.error('MegaCLI failed with status %i:\n%s\n%s', p.returncode,
                       p.stdout.read(), p.stderr.read())
        return p.returncode

    def set_ld_properties(self, devs, props):
        rc = []
        for dev in devs:
            for prop in props:
                rc.append(self._ldsetprop(dev, prop))
        return rc


def try_read(fn):
    try:
        with open(p.join(fn)) as f:
            return f.read().strip()
    except FileNotFoundError:
        return ''


def query_sysfs():
    devs = []
    for path in sorted(glob('/sys/block/sd?') + glob('/sys/block/nvme*')):
        sd = p.basename(path)
        vendor = try_read(p.join(path, 'device/vendor'))
        model = try_read(p.join(path, 'device/model'))
        with open(p.join(path, 'queue/rotational')) as f:
            rotational = int(f.read().strip())
        dev = BlockDev(sd, vendor, model, ssd=(rotational == 0))
        devs.append(dev)
    return devs


def query_controller(megacli):
    out = subprocess.check_output([megacli, '-LdPdInfo', '-aALL'])
    return out.decode('ascii')


class Tokenizer:

    def __init__(self, out):
        self.raw = out.splitlines()
        self.ptr = -1

    def __iter__(self):
        return self

    def __next__(self):
        while True:
            self.ptr += 1
            if self.ptr >= len(self.raw):
                raise StopIteration
            try:
                key, val = self.raw[self.ptr].split(':', 1)
            except ValueError:
                continue
            key = key.strip()
            val = val.strip()
            if key == '':
                continue
            return key, val

    next = __next__  # compatibility with older Python versions


class ControllerInfo:

    def __init__(self, ld, is_ssd, is_multi):
        self.ld = ld
        self.is_ssd = is_ssd
        self.is_multi = is_multi


def parse_ldpd(ldpd_info):
    tok = Tokenizer(ldpd_info)
    ld = None
    media_type = None
    res = []
    for (key, val) in tok:
        if key == 'Virtual Drive':
            ld = int(val.split()[0])
            media_type = None
        if key == 'Media Type':
            if not media_type:
                media_type = val
                res.append(
                    ControllerInfo(ld, val == 'Solid State Device', False))
            else:
                # additional PDs in a RAID device
                if media_type != val:
                    raise RuntimeError('mixed media types in LD {}'.format(ld))
                res[-1].is_multi = True
    return res


def update_media_type(devs, controller_info):
    lsi_devs = [d for d in devs if d.lsi]
    if len(lsi_devs) != len(controller_info):
        raise RuntimeError(
            'device count from sysfs does not match megacli output',
            len(lsi_devs), len(controller_info))
    for i, dev in enumerate(lsi_devs):
        dev.update_from_ldpd(controller_info[i])


# === high level actions ===


def auto_tune_lsi(devs, megacli):
    with open('MegaSAS.log', 'a') as log:
        print('\n### fc-blockdev {}'.format(time.ctime()), file=log)
    rc = [0]
    single = [d for d in devs if d.lsi and not d.multidisk]
    multi = [d for d in devs if d.lsi and d.multidisk]
    updater = MegaCliUpdate(megacli)
    rc += updater.set_ld_properties(single, ['NORA', 'WT', 'Direct'])
    rc += updater.set_ld_properties(multi,
                                    ['ADRA', 'WB', 'Cached', 'NoCachedBadBBU'])
    if max(rc) > 0:
        raise RuntimeError('MegaCLI failure')


def auto_tune_kernel(devs):
    for hdd in [d for d in devs if not d.ssd]:
        _log.info(hdd)
        hdd.set_sysfs('queue/read_ahead_kb', '256')
        hdd.set_sysfs('queue/scheduler', 'bfq')
        # hdd.set_sysfs('queue/iosched/front_merges', '1')
        if hdd.multidisk:
            hdd.set_sysfs('queue/nr_requests', '64')
        else:  # single disk
            hdd.set_sysfs('queue/nr_requests', '4')
    for ssd in [d for d in devs if d.ssd]:
        if not ssd.kernel.startswith('sd'):
            continue  # leave NVMe SSDs alone
        _log.info(ssd)
        ssd.set_sysfs('queue/read_ahead_kb', '64')
        if ssd.lsi:
            ssd.set_sysfs('queue/rotational', '0')
            ssd.set_sysfs('queue/nr_requests', '4')
        ssd.set_sysfs('queue/scheduler', 'none')


def filter_dev(patterns, devs):
    patterns = [re.compile(p) for p in patterns]
    return [d for d in devs if any(p.search(d.kernel) for p in patterns)]


def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        '-a',
        '--auto-tune',
        default=False,
        action='store_true',
        help='apply kernel settings and LSI settings (if '
        'appropriate)')
    a.add_argument('-v', '--verbose', default=False, action='store_true')
    a.add_argument('--megacli', default='MegaCli64')
    a.add_argument(
        'DEV',
        default=['^sd', '^nvme'],
        nargs='*',
        help='tune only block devices matching regex. May be given '
        'multiple times (default: %(default)s)')
    args = a.parse_args()
    if args.verbose:
        logging.basicConfig(
            level=logging.DEBUG,
            format='fc-blockdev: %(levelname)s %(message)s')
    else:
        logging.basicConfig(
            level=logging.INFO, format='fc-blockdev: %(message)s')
    os.chdir('/var/log')  # let MegaCLI not log to the current dir
    devs = query_sysfs()
    if not devs:
        _log.error('found no devices')
        sys.exit(0)
    if any(d.lsi for d in devs):
        controller_info = parse_ldpd(query_controller(args.megacli))
        update_media_type(devs, controller_info)
    patterns = args.DEV
    devs = filter_dev(patterns, devs)
    if not devs:
        _log.error('no matching devices')
        sys.exit(1)
    _log.info('Block device survey')
    for d in devs:
        _log.info('%s', d)
    if args.auto_tune:
        _log.info('Tuning sysfs kernel settings')
        auto_tune_kernel(devs)
        _log.info('Tuning RAID adapter settings')
        auto_tune_lsi(devs, args.megacli)


if __name__ == '__main__':
    main()

# === Tests ===

MEGACLI_OUT = """\
Adapter #0

Number of Virtual Disks: 5
Virtual Drive: 0 (Target Id: 0)
Name                :
RAID Level          : Primary-1, Secondary-0, RAID Level Qualifier-0
Number Of Drives    : 2
Span Depth          : 1
Default Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Disk Cache Policy   : Disabled
Number of Spans: 1
Span: 0 - Number of PDs: 2

PD: 0 Information
Enclosure Device ID: 252
Slot Number: 0
Drive's position: DiskGroup: 0, Span: 0, Arm: 0
PD Type: SATA

Raw Size: 465.761 GB [0x3a386030 Sectors]
Media Type: Hard Disk Device
Drive has flagged a S.M.A.R.T alert : No




PD: 1 Information
Enclosure Device ID: 252
Slot Number: 1
Drive's position: DiskGroup: 0, Span: 0, Arm: 1
PD Type: SATA

Raw Size: 465.761 GB [0x3a386030 Sectors]
Media Type: Hard Disk Device
Drive has flagged a S.M.A.R.T alert : No



Virtual Drive: 1 (Target Id: 1)
Name                :
RAID Level          : Primary-0, Secondary-0, RAID Level Qualifier-0
Number Of Drives    : 1
Span Depth          : 1
Default Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Disk Cache Policy   : Disabled
Number of Spans: 1
Span: 0 - Number of PDs: 1

PD: 0 Information
Enclosure Device ID: 252
Slot Number: 3
Drive's position: DiskGroup: 5, Span: 0, Arm: 0
PD Type: SAS

Raw Size: 558.911 GB [0x45dd2fb0 Sectors]
Media Type: Solid State Device
Drive has flagged a S.M.A.R.T alert : No



Virtual Drive: 2 (Target Id: 2)
Name                :
RAID Level          : Primary-0, Secondary-0, RAID Level Qualifier-0
Number Of Drives    : 1
Span Depth          : 1
Default Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Number of Spans: 1
Span: 0 - Number of PDs: 1

PD: 0 Information
Enclosure Device ID: 252
Slot Number: 4
Drive's position: DiskGroup: 6, Span: 0, Arm: 0
PD Type: SAS

Raw Size: 558.911 GB [0x45dd2fb0 Sectors]
Media Type: Hard Disk Device
Drive has flagged a S.M.A.R.T alert : No



Virtual Drive: 3 (Target Id: 3)
Name                :
RAID Level          : Primary-0, Secondary-0, RAID Level Qualifier-0
Number Of Drives    : 1
Span Depth          : 1
Default Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Number of Spans: 1
Span: 0 - Number of PDs: 1

PD: 0 Information
Enclosure Device ID: 252
Slot Number: 2
Drive's position: DiskGroup: 4, Span: 0, Arm: 0
PD Type: SATA

Raw Size: 238.474 GB [0x1dcf32b0 Sectors]
Media Type: Solid State Device
Drive has flagged a S.M.A.R.T alert : No



Virtual Drive: 4 (Target Id: 4)
Name                :
RAID Level          : Primary-0, Secondary-0, RAID Level Qualifier-0
Number Of Drives    : 1
Span Depth          : 1
Default Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Current Cache Policy: WriteBack, ReadAheadNone, Cached, No Write Cache if Bad BBU
Number of Spans: 1
Span: 0 - Number of PDs: 1

PD: 0 Information
Enclosure Device ID: 252
Slot Number: 5
Drive's position: DiskGroup: 1, Span: 0, Arm: 0
PD Type: SATA

Raw Size: 931.512 GB [0x74706db0 Sectors]
Media Type: Hard Disk Device
Drive has flagged a S.M.A.R.T alert : No



Exit Code: 0x00
"""


def test_tokenize_iter():
    t = Tokenizer(MEGACLI_OUT)
    assert next(t) == ('Number of Virtual Disks', '5')
    assert next(t) == ('Virtual Drive', '0 (Target Id: 0)')
    assert next(t) == ('Name', '')
    assert next(t) == ('RAID Level',
                       'Primary-1, Secondary-0, RAID Level Qualifier-0')


def test_tokenize_stopiteration():
    t = Tokenizer(MEGACLI_OUT)
    assert len(list(t)) == 97


def test_parse_ldpdinfo():
    info = parse_ldpd(MEGACLI_OUT)
    assert [ld.is_ssd for ld in info] == [False, True, False, True, False]
    assert [ld.is_multi for ld in info] == [True, False, False, False, False]


def test_fix_mediatype():
    devs = [
        BlockDev('sda', 'ATA'),
        BlockDev('sdb', 'LSI'),
        BlockDev('sdc', 'LSI'),
        BlockDev('sdd', 'LSI'),
        BlockDev('sde', 'LSI'),
        BlockDev('sdb', 'LSI'),
        BlockDev('nvme0n0', 'Intel', ssd=True), ]
    update_media_type(devs, parse_ldpd(MEGACLI_OUT))
    assert [(d.ssd, d.lsi_ld) for d in devs] == [
        (False, None),  # no LSI dev
        (False, 0),  # 5 LSI devs follow
        (True, 1),
        (False, 2),
        (True, 3),
        (False, 4),
        (True, None),  # no LSI dev
    ]


def test_lsi_count_mismatch():
    devs = [
        BlockDev('sda', 'ATA'),
        BlockDev('sdb', 'LSI'), ]
    try:
        update_media_type(devs, parse_ldpd(MEGACLI_OUT))
    except RuntimeError:
        return
    assert False, 'RuntimeError expected'


def test_filter_dev():
    devs = [BlockDev('sda', ''), BlockDev('nvme0n1', ''), BlockDev('md0', '')]
    assert filter_dev([], devs) == []
    assert filter_dev(['sda'], devs) == devs[0:1]
    assert filter_dev(['^sd', '^nvme'], devs) == devs[0:2]
