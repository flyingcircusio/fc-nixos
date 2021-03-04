#!/usr/bin/env python3
import argparse
import configparser
import glob
import json
import os
import re
import resource
import shutil
import socket
import subprocess
import sys
import time
from subprocess import PIPE, run

DEFAULT_JOURNAL_SIZE = 10

MKFS_XFS_OPTS = ['-m', 'crc=1,finobt=1', '-i', 'size=2048', '-K']
MOUNT_XFS_OPTS = "nodev,nosuid,noatime,nodiratime,logbsize=256k"


def run_ceph(*args):
    result = run(['ceph', '-f', 'json'] + list(args),
                 stdout=subprocess.PIPE,
                 check=True)
    return json.loads(result.stdout)


def query_lvm(*args):
    result = run(list(args) + ['--units', 'b', '--nosuffix', '--separator=,'],
                 stdout=subprocess.PIPE,
                 check=True)
    output = result.stdout.decode('ascii')
    lines = output.splitlines()
    results = []
    if lines:
        header = lines.pop(0)
        keys = header.strip().split(',')
        for line in lines:
            results.append(dict(zip(keys, line.strip().split(','))))
    return results


def wait_for_clean_cluster():
    while True:
        status = run_ceph('health', 'detail')
        peering = down = blocked = False
        for item in status['summary']:
            if 'pgs peering' in item['summary']:
                peering = True
                print(item['summary'])
            if 'in osds are down' in item['summary']:
                down = True
                print(item['summary'])
            if 'requests are blocked' in item['summary']:
                blocked = True
                print(item['summary'])

        if not peering and not down and not blocked:
            break

        # Don't be too fast here.
        time.sleep(5)


def create_osd(device, journal, journal_size, crush_location):
    assert '=' in crush_location
    assert journal in ['internal', 'external']
    assert os.path.exists(device)

    print("Creating OSD ...")
    id = int(run_ceph('osd', 'create')['osdid'])
    print(f'OSDID={id}')

    # XXX duplicated below
    servicename = f'ceph.osd.{id}'
    initscript = f'/etc/init.d/{servicename}'
    datadir = f'/srv/ceph/osd/ceph-{id}'
    name = f'osd.{id}'

    # These are the new format VG/LV:
    #   /dev/vgosd-1/ceph-osd-1
    #   /dev/vgjnlXX/ceph-jnl-1
    # Note that this uses the global numbering, not our previous local
    # numbering
    lvm_vg = f'vgosd-{id}'
    lvm_lv = f'ceph-osd-{id}'
    lvm_journal = f'ceph-jnl-{id}'
    lvm_data_device = f'/dev/{lvm_vg}/{lvm_lv}'

    if not os.path.exists(datadir):
        os.makedirs(datadir)

    run(['sgdisk', '-Z', device], check=True)
    run(['sgdisk', '-a', '8192', '-n', '1:0:0', '-t', '1:8e00', device],
        check=True)

    for partition in [f'{device}1', f'{device}p1']:
        if os.path.exists(partition):
            break
    else:
        raise RuntimeError(f'Could not find partition for PV on {device}')

    run(['pvcreate', partition], check=True)
    run(['vgcreate', lvm_vg, partition], check=True)

    # External journal
    if journal == 'external':
        # - Find suitable journal VG: the one with the most free bytes
        lvm_journal_vg = query_lvm('vgs', '-S', 'vg_name=~^vgjnl[0-9][0-9]$',
                                   '-o', 'vg_name,vg_free', '-O',
                                   '-vg_free')[0]['VG']
        print(f'Creating external journal on {lvm_journal_vg} ...')
        run([
            'lvcreate', '-W', 'y', f'-L{journal_size}g', f'-n{lvm_journal}',
            lvm_journal_vg
        ])
        lvm_journal_path = f'/dev/{lvm_journal_vg}/{lvm_journal}'
    elif journal == 'internal':
        print(f'Creating internal journal on {lvm_vg} ...')
        run([
            'lvcreate', '-W', 'y', f'-L{journal_size}g', f'-n{lvm_journal}',
            lvm_vg
        ])
        lvm_journal_path = f'/dev/{lvm_vg}/{lvm_journal}'
    else:
        raise ValueError(f'Invalid journal type: {journal}')

    # Create OSD LV on remainder of the VG
    run(['lvcreate', '-W', 'y', '-l100%vg', f'-n{lvm_lv}', lvm_vg], check=True)

    # Create OSD filesystem
    run(['mkfs.xfs', '-f', '-L', name] + MKFS_XFS_OPTS + [lvm_data_device],
        check=True)
    run(['sync'])
    run(['mount', '-t', 'xfs', '-o', MOUNT_XFS_OPTS, lvm_data_device, datadir],
        check=True)

    # Compute CRUSH weight (1.0 == 1TiB)
    lvm_lv_esc = re.escape(lvm_lv)
    size = query_lvm('lvs', '-S', f'lv_name=~^{lvm_lv_esc}$', '-o',
                     'lv_size')[0]['LSize']
    weight = float(size) / 1024**4

    run([
        'ceph-osd', '-i',
        str(id), '--mkfs', '--mkkey', '--mkjournal', '--osd-data', datadir,
        '--osd-journal', lvm_journal_path
    ],
        check=True)

    run([
        'ceph', 'auth', 'add', name, 'osd', 'allow *', 'mon', 'allow rwx',
        '-i', f'{datadir}/keyring'
    ],
        check=True)

    run(['ceph', 'osd', 'crush', 'add', name,
         str(weight), crush_location],
        check=True)

    activate_osd(id)


def is_osd_mounted(id):
    MAPPED_NAME = f'vgosd--{id}-ceph--osd--{id}'
    MOUNTPOINT = f'/srv/ceph/osd/ceph-{id}'
    result = run(['lsblk', '-o', 'name,mountpoint', '-r'],
                 stdout=subprocess.PIPE,
                 check=True)
    output = result.stdout.decode('ascii')
    lines = output.splitlines()
    header = lines.pop(0)
    keys = [x.lower() for x in header.strip().split(' ')]
    for line in lines:
        result = dict(zip(keys, line.strip().split(' ')))
        result.setdefault('mountpoint', '')
        if result['name'] == MAPPED_NAME:
            if result['mountpoint'] == MOUNTPOINT:
                return True
            elif not result['mountpoint']:
                return False
            else:
                raise RuntimeError(
                    f'OSD {id} mounted at unexpected mountpoint '
                    f'{result["mountpoint"]}')
    raise RuntimeError(f'Mapped volume {MAPPED_NAME} not found for OSD {id}')


def find_mountpoint(path):
    for line in open('/etc/fstab', encoding='ascii').readlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith('#'):
            continue
        fs, mountpoint, *_ = line.split()
        if mountpoint == path:
            return fs
    raise KeyError(path)


def _list_local_osd_ids():
    vgs = query_lvm('vgs', '-S', f'vg_name=~^vgosd\\-[0-9]+$', '-o', 'vg_name')
    return [int(vg['VG'].replace('vgosd-', '', 1)) for vg in vgs]


def _activate_osd(id):
    # Relocating OSDs: create journal if missing?
    print(f'Activating OSD {id}...')

    # XXX duplicated below
    servicename = f'ceph.osd.{id}'
    initscript = f'/etc/init.d/{servicename}'
    datadir = f'/srv/ceph/osd/ceph-{id}'
    name = f'osd.{id}'

    # These are the new format VG/LV:
    #   /dev/vgosd-1/ceph-osd-1
    #   /dev/vgjnlXX/ceph-jnl-1
    # Note that this uses the global numbering, not our previous local
    # numbering
    lvm_vg = f'vgosd-{id}'
    lvm_lv = f'ceph-osd-{id}'
    lvm_journal = f'ceph-jnl-{id}'
    lvm_data_device = f'/dev/{lvm_vg}/{lvm_lv}'
    pidfile = f'/run/ceph/osd.{id}.pid'
    # Check VG for journal
    lvm_journal_esc = re.escape(lvm_journal)
    try:
        lvm_journal_vg = query_lvm('lvs', '-S',
                                   f'lv_name=~^{lvm_journal_esc}$', '-o',
                                   'vg_name')[0]['VG']
        lvm_journal_path = f'/dev/{lvm_journal_vg}/{lvm_journal}'
    except IndexError:
        print(
            f"No journal found for OSD {id} - does this OSD exist on this host?"
        )
        sys.exit(1)

    if not is_osd_mounted(id):
        if not os.path.exists(datadir):
            os.makedirs(datadir)
        run([
            'mount', '-t', 'xfs', '-o', MOUNT_XFS_OPTS, lvm_data_device,
            datadir
        ],
            check=True)

    resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))
    run([
        'ceph-osd', '-i',
        str(id), '--pid-file', pidfile, '--osd-data', datadir, '--osd-journal',
        lvm_journal_path
    ],
        check=True)


def activate_osd(id):
    try:
        run(['fc-blockdev', '-a'])
    except Exception:
        pass
    if id == 'all':
        osd_ids = _list_local_osd_ids()
    else:
        osd_ids = [int(id)]

    for osd_id in osd_ids:
        try:
            _activate_osd(osd_id)
        except Exception as e:
            print(e)


def _deactivate_osd(id, flush=True):
    # deactivate (shutdown osd, remove things but don't delete it, make
    # the osd able to be relocated somewhere else)

    pidfile = f'/run/ceph/osd.{id}.pid'

    print(f'Stopping OSD {id} ...')
    with open(pidfile) as f:
        pid = f.read().strip()
    run(['kill', pid])
    import time
    time.sleep(10)

    datadir = f'/srv/ceph/osd/ceph-{id}'

    lvm_journal = f'ceph-jnl-{id}'
    lvm_journal_esc = re.escape(lvm_journal)
    lvm_journal_vg = query_lvm('lvs', '-S', f'lv_name=~^{lvm_journal_esc}$',
                               '-o', 'vg_name')[0]['VG']
    lvm_journal_path = f'/dev/{lvm_journal_vg}/{lvm_journal}'

    # flush journal?
    if flush:
        print(f'Flushing journal for OSD {id} ...')
        run([
            'ceph-osd', '-i',
            str(id), '--flush-journal', '--osd-data', datadir, '--osd-journal',
            lvm_journal_path
        ],
            check=True)

    # Unmount?


def deactivate_osd(id):
    if id == 'all':
        osd_ids = _list_local_osd_ids()
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        try:
            _deactivate_osd(osd_id)
        except Exception as e:
            print(e)


def reactivate_osd(id):
    if id == 'all':
        osd_ids = _list_local_osd_ids()
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        wait_for_clean_cluster()
        try:
            _deactivate_osd(osd_id, flush=False)
            _activate_osd(osd_id)
        except Exception as e:
            print(e)


def _migrate_osd_v1(id):
    print(f'Migrating OSD {id} from v1 to v2')
    # check mountpoint, correlate with local id
    datadir = f'/srv/ceph/osd/ceph-{id}'

    mount_source = find_mountpoint(datadir)
    assert mount_source.startswith('/dev/vgosd')
    mount_source = mount_source.replace('/dev/', '', 1)
    vg, lv = mount_source.split('/')
    assert lv.startswith('ceph-osd')
    vg_num = vg.replace('vgosd', '', 1)
    lv_num = lv.replace('ceph-osd', '', 1)
    assert vg_num == lv_num
    assert int(vg_num, base=10) == int(lv_num, base=10)
    local_osd_id = vg_num  # need to keep this as str due to leading zeroes

    name = f'osd.{id}'
    service = f'ceph.{name}'
    initscript = f'/etc/init.d/{service}'

    new_lvm_vg = f'vgosd-{id}'
    new_lvm_lv = f'ceph-osd-{id}'
    new_lvm_journal = f'ceph-jnl-{id}'

    if not os.path.exists(datadir):
        print(f'Did not find datadir for OSD {id}')

    print('Stopping OSD and removing init script ... ')
    run([initscript, 'stop'], check=True)
    run(['rc-update', 'del', service])
    os.unlink(initscript)

    print('Removing from ceph.conf ... ')
    config = configparser.ConfigParser()
    config.read('/etc/ceph/ceph.conf')
    if name in config.sections():
        config.remove_section(name)
        with open('/etc/ceph/ceph.conf', 'w') as ceph_conf:
            config.write(ceph_conf)

    print('Unmounting ... ')
    run(['umount', datadir])

    print('Removing from fstab ...')
    # remove from fstab
    lines = open('/etc/fstab', encoding='ascii').readlines()
    with open('/etc/.fstab.ceph', 'w') as f:
        for original_line in lines:
            line = original_line.strip()
            if not line or line.startswith('#'):
                f.write(original_line)
                continue
            fs, mountpoint, *_ = line.split()
            if mountpoint == datadir:
                continue
            f.write(original_line)
    os.rename('/etc/.fstab.ceph', '/etc/fstab')

    print('Renaming OSD LV ...')
    run([
        'lvrename', f'vgosd{local_osd_id}', f'ceph-osd{local_osd_id}',
        new_lvm_lv
    ])

    print('Renaming OSD journal LV ...')
    try:
        journal_vg = query_lvm('lvs', '-S',
                               f'lv_name=~^ceph-jnl{local_osd_id}$', '-o',
                               'vg_name')[0]['VG']
    except IndexError:
        pass
    else:
        run([
            'lvrename', journal_vg, f'ceph-jnl{local_osd_id}', new_lvm_journal
        ],
            check=True)

    print('Renaming OSD VG ...')
    run(['vgrename', f'vgosd{local_osd_id}', new_lvm_vg], check=True)

    activate_osd(id)


def migrate_osd_v1(id):
    if ',' in id:
        osd_ids = id.split(',')
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        wait_for_clean_cluster()
        try:
            _migrate_osd_v1(osd_id)
        except Exception as e:
            print(e)


def _rebuild_osd(osd_id):
    print(f'Rebuilding OSD {osd_id} from scratch')

    # What's the physical disk?
    pvs = query_lvm('pvs', '-S', f'vg_name=vgosd-{osd_id}', '--all')
    if not len(pvs) == 1:
        raise ValueError(f"Unexpected number of PVs in OSD's RG: {len(pvs)}")
    pv = pvs[0]['PV']
    # Find the parent
    candidates = run(['lsblk', pv, '-o', 'name,pkname', '-r'],
                     stdout=subprocess.PIPE,
                     check=True)
    candidates = candidates.stdout.decode('ascii').splitlines()
    candidates.pop(0)

    for line in candidates:
        name, pkname = line.split()
        if name == pv.split('/')[-1]:
            device = f'/dev/{pkname}'
            break
    else:
        raise ValueError(f"Could not find parent for PV: {pv}")
    print("device=", device)

    # Is the journal internal or external?
    lvs = query_lvm('lvs', '-S', f'vg_name=vgosd-{osd_id}')
    if len(lvs) == 1:
        journal = 'external'
    elif len(lvs) == 2:
        journal = 'internal'
    else:
        raise ValueError(f"Unexpected number of LVs in OSD's RG: {len(lvs)}")
    print("--journal=", journal)

    # what's the crush location (host?)
    crush_location = "host={0}".format(
        run_ceph('osd', 'find', osd_id)['crush_location']['host'])

    print("--crush-location=", crush_location)

    print(f'{sys.argv[0]} osd destroy {osd_id}')
    destroy_osd(osd_id)

    print(
        f'{sys.argv[0]} osd create {device} --journal={journal} --crush-location={crush_location}'
    )
    create_osd(device, journal, DEFAULT_JOURNAL_SIZE, crush_location)


def rebuild_osd(id):
    if ',' in id:
        osd_ids = id.split(',')
    elif id == 'all':
        osd_ids = [str(x) for x in _list_local_osd_ids()]
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        try:
            _rebuild_osd(osd_id)
        except Exception as e:
            print(e)


def _migrate_osd_rocksdb(id):
    osd_path = f'/srv/ceph/osd/ceph-{id}'
    print(f'Migrating OSD {id} to RocksDB ...')
    superblock = open(f'{osd_path}/superblock', 'r').read()
    if 'rocksdb' in superblock:
        print('\tAlready a RocksDB OSD.')
        return
    if 'leveldb' not in superblock:
        print('\tUnknown superblock.')
        return
    print('\tFound LevelDB superblock.')
    deactivate_osd(id)
    os.chdir(f'{osd_path}/current')
    os.rename('omap', 'omap.leveldb')
    run([
        'ceph-kvstore-tool', 'leveldb', 'omap.leveldb', 'store-copy', 'omap',
        '10000', 'rocksdb'
    ],
        check=True)
    run(['ceph-osdomap-tool', '--omap-path', 'omap', '--command', 'check'],
        check=True)
    shutil.rmtree('omap.leveldb')
    os.chdir('..')
    with open(f'{osd_path}/superblock', 'w') as f:
        superblock = superblock.replace('leveldb', 'rocksdb')
        f.write(superblock)
    activate_osd(id)


def migrate_osd_rocksdb(id):
    if id == 'all':
        osd_ids = _list_local_osd_ids()
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        # No try/except here: we do not want to continue destroying more OSDs
        # in case something goes wrong.
        _migrate_osd_rocksdb(osd_id)
        wait_for_clean_cluster()


def _migrate_osd_leveldb(id):
    osd_path = f'/srv/ceph/osd/ceph-{id}'
    print(f'Migrating OSD {id} to LevelDB ...')
    superblock = open(f'{osd_path}/superblock', 'r').read()
    if 'leveldb' in superblock:
        print('\tAlready a LevelDB OSD.')
        return
    if 'rocksdb' not in superblock:
        print('\tUnknown superblock.')
        return
    print('\tFound RocksDB superblock.')
    _deactivate_osd(id, flush=False)
    os.chdir(f'{osd_path}/current')
    os.rename('omap', 'omap.rocksdb')
    run([
        'ceph-kvstore-tool', 'rocksdb', 'omap.rocksdb', 'store-copy', 'omap',
        '10000', 'leveldb'
    ],
        check=True)
    # This check doesn't work w/ LevelDB it seems ...
    # run(['ceph-osdomap-tool', '--omap-path', 'omap',  '--command', 'check'], check=True)
    shutil.rmtree('omap.rocksdb')
    os.chdir('..')
    with open(f'{osd_path}/superblock', 'w') as f:
        superblock = superblock.replace('rocksdb', 'leveldb')
        f.write(superblock)
    activate_osd(id)


def migrate_osd_leveldb(id):
    if id == 'all':
        osd_ids = _list_local_osd_ids()
    else:
        osd_ids = [id]

    for osd_id in osd_ids:
        # No try/except here: we do not want to continue destroying more OSDs
        # in case something goes wrong.
        _migrate_osd_leveldb(osd_id)
        wait_for_clean_cluster()


def destroy_osd(id):
    if int(id) not in _list_local_osd_ids():
        print(f"Refusing to destroy remote OSD {id} ...")
        sys.exit(1)

    print(f"Destroying OSD {id} ...")

    # XXX duplicated below
    servicename = f'ceph.osd.{id}'
    initscript = f'/etc/init.d/{servicename}'
    datadir = f'/srv/ceph/osd/ceph-{id}'

    # These are the new format VG/LV:
    #   /dev/vgosd-1/ceph-osd-1
    #   /dev/vgjnlXX/ceph-jnl-1
    # Note that this uses the global numbering, not our previous local
    # numbering
    lvm_vg = f'vgosd-{id}'
    lvm_lv = f'ceph-osd-{id}'
    lvm_journal = f'ceph-jnl-{id}'
    lvm_data_device = f'/dev/{lvm_vg}/{lvm_lv}'

    # Try shutting it down first
    try:
        _deactivate_osd(id, flush=False)
    except Exception as e:
        print(e)

    # Remove from crush map
    run(['ceph', 'osd', 'crush', 'remove', f'osd.{id}'])
    # Remove authentication
    run(['ceph', 'auth', 'del', f'osd.{id}'])
    # Delete OSD object
    run(['ceph', 'osd', 'rm', str(id)])

    # Unmount
    if os.path.exists(datadir):
        run(['umount', '-f', datadir])
        os.rmdir(datadir)

    # Delete new-style LVs
    run(['wipefs', '-q', '-a', lvm_data_device])
    run(['lvremove', '-f', lvm_data_device])

    try:
        lvm_journal_esc = re.escape(lvm_journal)
        journal_vg = query_lvm('lvs', '-S', f'lv_name=~^{lvm_journal_esc}$',
                               '-o', 'vg_name')[0]['VG']
    except IndexError:
        pass
    else:
        run(['lvremove', '-f', f'/dev/{journal_vg}/{lvm_journal}'])

    lvm_vg_esc = re.escape(lvm_vg)
    try:
        pv = query_lvm('pvs', '-S', f'vg_name=~^{lvm_vg_esc}$', '-o',
                       'pv_name')[0]
    except IndexError:
        pass
    else:
        run(['vgremove', '-f', lvm_vg])
        run(['pvremove', pv['PV']])

    # Force remove old mapper files
    delete_paths = (glob.glob(f'/dev/vgosd-{id}/*') +
                    glob.glob(f'/dev/mapper/vgosd--{id}-*') +
                    [f'/dev/vgosd-{id}'])
    for x in delete_paths:
        if not os.path.exists(x):
            continue
        print(x)
        if os.path.isdir(x):
            os.rmdir(x)
        else:
            os.unlink(x)


def main():
    hostname = socket.gethostname()

    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers()

    osd = subparsers.add_parser('osd', help='Manage OSDs.')
    osd_sub = osd.add_subparsers()

    parser_destroy = osd_sub.add_parser('destroy', help='Destroy an OSD.')
    parser_destroy.add_argument('id', type=int, help='ID of OSD to destroy.')
    parser_destroy.set_defaults(func=destroy_osd)

    parser_activate = osd_sub.add_parser('create',
                                         help='Create activate an OSD.')
    parser_activate.add_argument('device', help='Blockdevice to use')
    parser_activate.add_argument(
        '--journal',
        default='external',
        choices=['external', 'internal'],
        help='Type of journal (on same disk or external)')
    parser_activate.add_argument('--journal-size',
                                 default=DEFAULT_JOURNAL_SIZE,
                                 type=int,
                                 help='Size of journal.')
    parser_activate.add_argument('--crush-location',
                                 default=f'host={hostname}')
    parser_activate.set_defaults(func=create_osd)

    parser_activate = osd_sub.add_parser('activate', help='Activate an OSD.')
    parser_activate.add_argument(
        'id',
        help='ID of OSD to activate. Use `all` to activate all local OSD.')
    parser_activate.set_defaults(func=activate_osd)

    parser_deactivate = osd_sub.add_parser('deactivate',
                                           help='Deactivate an OSD.')
    parser_deactivate.add_argument(
        'id',
        help='ID of OSD to deactivate. Use `all` to deactivate all local OSD.')
    parser_deactivate.set_defaults(func=deactivate_osd)

    parser_reactivate = osd_sub.add_parser('reactivate',
                                           help='Reactivate an OSD.')
    parser_reactivate.add_argument(
        'id',
        help=
        'ID of OSDs to reactivate (activate and deactivate). Use `all` to reactivate all local OSD.'
    )
    parser_reactivate.set_defaults(func=reactivate_osd)

    parser_migrate_v1 = osd_sub.add_parser(
        'rebuild', help='Rebuild an OSD by destroying and creating it again.')
    parser_migrate_v1.add_argument(
        'id',
        help='ID of OSD to migrate. Use `all` to convert all local OSDs.')
    parser_migrate_v1.set_defaults(func=rebuild_osd)

    parser_migrate_v1 = osd_sub.add_parser(
        'migrate-v1', help='Migrate an OSD from layout v1 -> v2.')
    parser_migrate_v1.add_argument(
        'id',
        help='ID of OSD to migrate. Use `all` to convert all local OSDs.')
    parser_migrate_v1.set_defaults(func=migrate_osd_v1)

    parser_migrate_rocksdb = osd_sub.add_parser(
        'migrate-rocksdb', help='Migrate an OSD from leveldb to rocksdb.')
    parser_migrate_rocksdb.add_argument(
        'id',
        help='ID of OSD to migrate. Use `all` to convert all local OSDs.')
    parser_migrate_rocksdb.set_defaults(func=migrate_osd_rocksdb)

    parser_migrate_leveldb = osd_sub.add_parser(
        'migrate-leveldb', help='Migrate an OSD from RocksDB to LevelDB.')
    parser_migrate_leveldb.add_argument(
        'id',
        help='ID of OSD to migrate. Use `all` to convert all local OSDs.')
    parser_migrate_leveldb.set_defaults(func=migrate_osd_leveldb)

    args = parser.parse_args()
    if not hasattr(args, 'func'):
        parser.print_help()
        sys.exit(1)

    func = args.func
    del args.func
    func(*args._get_args(), **dict(args._get_kwargs()))


if __name__ == '__main__':
    main()
