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
import tempfile
import threading
import time
from subprocess import PIPE, run


def run_ceph(*args):
    return run_json(['ceph', '-f', 'json'] + list(args))


def run_json(*args, **kw):
    result = run(
        *args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
        **kw)
    return json.loads(result.stdout)


def query_lvm(*args):
    result = run(
        list(args) + ['--units', 'b', '--nosuffix', '--separator=,'],
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


def vgs():
    return run_json(['vgs', '--reportformat', 'json'])['report'][0]['vg']


def lvs():
    return run_json(['lvs', '--reportformat', 'json'])['report'][0]['lv']


def find_journal_vgs():
    result = []
    for vg in vgs():
        if vg['vg_name'].startswith('vgjnl'):
            result.append(vg)
    return result


def find_lv_path(name):
    result = []
    for lv in lvs():
        if lv['lv_name'] == name:
            result.append(lv)
    if len(result) != 1:
        raise ValueError(f'Invalid number of LVs found: {len(result)}')
    lv = result[0]
    return f"/dev/{lv['vg_name']}/{lv['lv_name']}"


def is_mounted(path):
    result = run_json(['lsblk', '-J'])
    devices = result['blockdevices']
    while devices:
        device = devices.pop()
        if device['mountpoint'] == path:
            if device['type'] == 'lvm':
                return f'/dev/mapper/{device["name"]}'
            elif device['type'] in ['part', 'disk']:
                return f'/dev/{device["name"]}'
            else:
                raise ValueError(
                    f"Unknown block device type: {device['type']} ({device['name']})"
                )
        devices.extend(device.get('children', []))


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


def kill(pid_file):
    if not os.path.exists(pid_file):
        print(f'PID file {pid_file} found. Not killing.')
        return

    with open(pid_file) as f:
        pid = f.read().strip()
    run(['kill', pid], check=True)
    counter = 0
    while os.path.exists(f'/proc/{pid}'):
        counter += 1
        time.sleep(1)
        print('.', end='', flush=True)
        if not counter % 30:
            run(['kill', pid])
    print()


class OSDManager(object):

    def __init__(self):
        self.local_osd_ids = self._list_local_osd_ids()

    def _list_local_osd_ids(self, ):
        vgs = query_lvm('vgs', '-S', f'vg_name=~^vgosd\\-[0-9]+$', '-o',
                        'vg_name')
        return [int(vg['VG'].replace('vgosd-', '', 1)) for vg in vgs]

    def _parse_ids(self, ids, allow_non_local=False):
        if ids == 'all':
            return self.local_osd_ids
        ids = [int(x) for x in ids.split(',')]
        non_local = set(ids) - set(self.local_osd_ids)
        if non_local:
            if allow_non_local:
                print(f"WARNING: I was asked to operate on "
                      f"non-local OSDs: {non_local}")
                confirmation = input(f"To proceed enter `{allow_non_local}`: ")
                if confirmation != allow_non_local:
                    print("Confirmation was not given. Aborting.")
                    sys.exit(1)
            else:
                raise ValueError(
                    f"Refusing to operate on remote OSDs: {non_local}")
        return ids

    def create(self, device, journal, journal_size, crush_location):
        assert '=' in crush_location
        assert journal in ['internal', 'external']
        assert os.path.exists(device)

        print("Creating OSD ...")

        id_ = int(run_ceph('osd', 'create')['osdid'])
        print(f'OSDID={id_}')

        osd = OSD(id_)
        osd.create(device, journal, journal_size, crush_location)

    def activate(self, ids):
        ids = self._parse_ids(ids)
        run(['systemctl', 'start', 'fc-blockdev'])

        for id_ in ids:
            try:
                osd = OSD(id_)
                osd.activate()
            except Exception as e:
                print(e)

    def destroy(self, ids):
        ids = self._parse_ids(ids, allow_non_local=f'DESTROY {ids}')

        for id_ in ids:
            try:
                osd = OSD(id_)
                osd.destroy()
            except Exception as e:
                print(e)

    def deactivate(self, ids):
        ids = self._parse_ids(ids)

        threads = []
        for id_ in ids:
            try:
                osd = OSD(id_)
                thread = threading.Thread(target=osd.deactivate)
                thread.start()
                threads.append(thread)
            except Exception as e:
                print(e)

        for thread in threads:
            thread.join()

    def reactivate(self, ids):
        ids = self._parse_ids(ids)

        for id_ in ids:
            wait_for_clean_cluster()
            try:
                osd = OSD(id_)
                osd.deactivate(flush=False)
                osd.activate()
            except Exception as e:
                print(e)

    def rebuild(self, ids):
        ids = self._parse_ids(ids)

        for id_ in ids:
            try:
                osd = OSD(id_)
                osd.rebuild()
            except Exception as e:
                print(e)

    def prepare_journal(self, device):
        if not os.path.exists(device):
            print(f'Device does not exist: ')
        try:
            partition_table = run_json(['sfdisk', '-J',
                                        device])['partitiontable']
        except Exception as e:
            if b'does not contain a recognized partition table' not in e.stderr:
                # Not an empty disk, propagate the error
                raise
        else:
            if partition_table['partitions']:
                print('Device already has a partition. '
                      'Refusing to prepare journal VG.')
                sys.exit(1)

        ids = set()
        for journal_vg in query_lvm('vgs', '-S', 'vg_name=~^vgjnl[0-9][0-9]$',
                                    '-o', 'vg_name,vg_free'):
            id_ = int(journal_vg['VG'].replace('vgjnl', ''), 10)
            ids.add(id_)

        # find the first free number
        for id_ in range(99):
            if id_ not in ids:
                break
        else:
            raise ValueError("No free journal ID 0<=id<=99 found.")

        jnl_vg = 'vgjnl{:02d}'.format(id_)

        run(['sgdisk', '-Z', device], check=True)
        run(['sgdisk', '-a', '8192', '-n', '1:0:0', '-t', '1:8e00', device],
            check=True)

        for partition in [f'{device}1', f'{device}p1']:
            if os.path.exists(partition):
                break
        else:
            raise RuntimeError(f'Could not find partition for PV on {device}')

        run(['pvcreate', partition], check=True)
        run(['vgcreate', jnl_vg, partition], check=True)


class OSD(object):

    DEFAULT_JOURNAL_SIZE = 10

    MKFS_XFS_OPTS = ['-m', 'crc=1,finobt=1', '-i', 'size=2048', '-K']
    MOUNT_XFS_OPTS = "nodev,nosuid,noatime,nodiratime,logbsize=256k"

    def __init__(self, id):
        self.id = id

        self.MAPPED_NAME = f'vgosd--{self.id}-ceph--osd--{self.id}'
        self.MOUNTPOINT = f'/srv/ceph/osd/ceph-{self.id}'

        self.datadir = f'/srv/ceph/osd/ceph-{self.id}'
        self.lvm_vg = f'vgosd-{self.id}'
        self.lvm_vg_esc = re.escape(self.lvm_vg)
        self.lvm_lv = f'ceph-osd-{self.id}'
        self.lvm_journal = f'ceph-jnl-{self.id}'
        self.lvm_journal_esc = re.escape(self.lvm_journal)
        self.lvm_data_device = f'/dev/{self.lvm_vg}/{self.lvm_lv}'
        self.pid_file = f'/run/ceph/osd.{self.id}.pid'

        self.name = f'osd.{id}'

    def _locate_journal_lv(self):
        try:
            lvm_journal_vg = query_lvm('lvs', '-S',
                                       f'lv_name=~^{self.lvm_journal_esc}$',
                                       '-o', 'vg_name')[0]['VG']
            return f'/dev/{lvm_journal_vg}/{self.lvm_journal}'
        except IndexError:
            raise ValueError(f"No journal found for OSD {self.id} - "
                             "does this OSD exist on this host?")

    def is_mounted(self):
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
            if result['name'] == self.MAPPED_NAME:
                if result['mountpoint'] == self.MOUNTPOINT:
                    return True
                elif not result['mountpoint']:
                    return False
                else:
                    raise RuntimeError(
                        f'OSD {self.id} mounted at unexpected mountpoint '
                        f'{result["mountpoint"]}')
        raise RuntimeError(
            f'Mapped volume {self.MAPPED_NAME} not found for OSD {self.id}')

    def activate(self):
        # Relocating OSDs: create journal if missing?
        print(f'Activating OSD {self.id}...')

        # Check VG for journal
        lvm_journal = self._locate_journal_lv()

        if not self.is_mounted():
            if not os.path.exists(self.datadir):
                os.makedirs(self.datadir)
            run([
                'mount', '-t', 'xfs', '-o', self.MOUNT_XFS_OPTS,
                self.lvm_data_device, self.datadir],
                check=True)

        resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))
        run([
            'ceph-osd', '-i',
            str(self.id), '--pid-file', self.pid_file, '--osd-data',
            self.datadir, '--osd-journal', lvm_journal],
            check=True)

    def deactivate(self, flush=True):
        # deactivate (shutdown osd, remove things but don't delete it, make
        # the osd able to be relocated somewhere else)
        print(f'Stopping OSD {self.id} ...')
        kill(self.pid_file)

        if flush:
            print(f'Flushing journal for OSD {self.id} ...')
            run([
                'ceph-osd', '-i',
                str(self.id), '--flush-journal', '--osd-data', self.datadir,
                '--osd-journal',
                self._locate_journal_lv()],
                check=True)

    def create(self, device, journal, journal_size, crush_location):
        if not journal_size:
            journal_size = self.DEFAULT_JOURNAL_SIZE

        if not os.path.exists(self.datadir):
            os.makedirs(self.datadir)

        run(['sgdisk', '-Z', device], check=True)
        run(['sgdisk', '-a', '8192', '-n', '1:0:0', '-t', '1:8e00', device],
            check=True)

        for partition in [f'{device}1', f'{device}p1']:
            if os.path.exists(partition):
                break
        else:
            raise RuntimeError(f'Could not find partition for PV on {device}')

        run(['pvcreate', partition], check=True)
        run(['vgcreate', self.lvm_vg, partition], check=True)

        # External journal
        if journal == 'external':
            # - Find suitable journal VG: the one with the most free bytes
            lvm_journal_vg = query_lvm('vgs', '-S',
                                       'vg_name=~^vgjnl[0-9][0-9]$', '-o',
                                       'vg_name,vg_free', '-O',
                                       '-vg_free')[0]['VG']
            print(f'Creating external journal on {lvm_journal_vg} ...')
            run([
                'lvcreate', '-W', 'y', f'-L{journal_size}g',
                f'-n{self.lvm_journal}', lvm_journal_vg],
                check=True)
            lvm_journal_path = f'/dev/{lvm_journal_vg}/{self.lvm_journal}'
        elif journal == 'internal':
            print(f'Creating internal journal on {self.lvm_vg} ...')
            run([
                'lvcreate', '-W', 'y', f'-L{journal_size}g',
                f'-n{self.lvm_journal}', self.lvm_vg])
            lvm_journal_path = f'/dev/{self.lvm_vg}/{self.lvm_journal}'
        else:
            raise ValueError(f'Invalid journal type: {journal}')

        # Create OSD LV on remainder of the VG
        run([
            'lvcreate', '-W', 'y', '-l100%vg', f'-n{self.lvm_lv}', self.lvm_vg
        ],
            check=True)

        # Create OSD filesystem
        run(['mkfs.xfs', '-f', '-L', self.name] + self.MKFS_XFS_OPTS +
            [self.lvm_data_device],
            check=True)
        run(['sync'], check=True)
        run([
            'mount', '-t', 'xfs', '-o', self.MOUNT_XFS_OPTS,
            self.lvm_data_device, self.datadir],
            check=True)

        # Compute CRUSH weight (1.0 == 1TiB)
        lvm_lv_esc = re.escape(self.lvm_lv)
        size = query_lvm('lvs', '-S', f'lv_name=~^{lvm_lv_esc}$', '-o',
                         'lv_size')[0]['LSize']
        weight = float(size) / 1024**4

        run([
            'ceph-osd', '-i',
            str(self.id), '--mkfs', '--mkkey', '--mkjournal', '--osd-data',
            self.datadir, '--osd-journal', lvm_journal_path],
            check=True)

        run([
            'ceph', 'auth', 'add', self.name, 'osd', 'allow *', 'mon',
            'allow rwx', '-i', f'{self.datadir}/keyring'],
            check=True)

        run([
            'ceph', 'osd', 'crush', 'add', self.name,
            str(weight), crush_location],
            check=True)

        self.activate()

    def rebuild(self):
        print(f'Rebuilding OSD {self.id} from scratch')

        # What's the physical disk?
        pvs = query_lvm('pvs', '-S', f'vg_name={self.lvm_vg}', '--all')
        if not len(pvs) == 1:
            raise ValueError(
                f"Unexpected number of PVs in OSD's RG: {len(pvs)}")
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
        print(f"device={device}")

        # Is the journal internal or external?
        lvs = query_lvm('lvs', '-S', f'vg_name={self.lvm_vg}')
        if len(lvs) == 1:
            journal = 'external'
        elif len(lvs) == 2:
            journal = 'internal'
        else:
            raise ValueError(
                f"Unexpected number of LVs in OSD's RG: {len(lvs)}")
        print(f"--journal={journal}")

        # what's the crush location (host?)
        crush_location = "host={0}".format(
            run_ceph('osd', 'find', str(self.id))['crush_location']['host'])

        print(f"--crush-location={crush_location}")

        print('Destroying OSD ...')
        self.destroy()

        print('Creating OSD ...')
        print(f'command: fc-ceph osd create {device} --journal={journal} '
              f'--crush-location={crush_location}')

        # This is an "interesting" turn-around ...
        manager = OSDManager()
        manager.create(device, journal, 0, crush_location)

    def destroy(self):
        print(f"Destroying OSD {self.id} ...")

        try:
            self.deactivate(flush=False)
        except Exception as e:
            print(e)

        # Remove from crush map
        run(['ceph', 'osd', 'crush', 'remove', self.name])
        # Remove authentication
        run(['ceph', 'auth', 'del', self.name])
        # Delete OSD object
        run(['ceph', 'osd', 'rm', str(self.id)])

        if os.path.exists(self.datadir):
            run(['umount', '-f', self.datadir])
            os.rmdir(self.datadir)

        # Delete new-style LVs
        run(['wipefs', '-q', '-a', self.lvm_data_device])
        run(['lvremove', '-f', self.lvm_data_device])

        try:
            run(['lvremove', '-f', self._locate_journal_lv()])
        except Exception:
            pass

        try:
            pv = query_lvm('pvs', '-S', f'vg_name=~^{self.lvm_vg_esc}$', '-o',
                           'pv_name')[0]
        except IndexError:
            pass
        else:
            run(['vgremove', '-f', self.lvm_vg])
            run(['pvremove', pv['PV']])

        # Force remove old mapper files
        delete_paths = (
            glob.glob(f'/dev/vgosd-{self.id}/*') +
            glob.glob(f'/dev/mapper/vgosd--{self.id}-*') +
            [f'/dev/vgosd-{self.id}'])
        for x in delete_paths:
            if not os.path.exists(x):
                continue
            print(x)
            if os.path.isdir(x):
                os.rmdir(x)
            else:
                os.unlink(x)


class Monitor(object):

    def __init__(self):
        self.id = socket.gethostname()
        self.mon_dir = f'/srv/ceph/mon/ceph-{self.id}'
        self.pid_file = f'/run/ceph/mon.{self.id}.pid'

    def activate(self):
        print(f'Activating MON {self.id}...')
        resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))

        if not os.path.exists(self.mon_dir):
            os.makedirs(self.mon_dir)

        if not is_mounted(self.mon_dir):
            run([
                'mount', '-t', 'xfs', '-o', 'defaults,nodev,nosuid',
                'LABEL=ceph-mon', self.mon_dir],
                check=True)
        run(['ceph-mon', '-i', self.id, '--pid-file', self.pid_file],
            check=True)

    def deactivate(self):
        print(f'Stopping MON {self.id} ...')
        kill(self.pid_file)

    def reactivate(self):
        try:
            self.deactivate()
        except Exception:
            pass
        self.activate()

    def create(self, size='8g'):
        print(f'Creating MON {self.id}...')

        if os.path.exists(self.mon_dir):
            print('There already exists a mon dir. '
                  'Please destroy existing mon data first.')
            sys.exit(1)

        if not os.path.exists(self.mon_dir):
            os.makedirs(self.mon_dir)

        try:
            lvm_vg = find_journal_vgs()[0]['vg_name']
        except IndexError:
            print('Could not find a journal VG. Please prepare a journal '
                  'VG first using `fc-ceph osd prepare-journal`.')
            sys.exit(1)

        lvm_lv = f'ceph-mon'
        lvm_data_device = f'/dev/{lvm_vg}/{lvm_lv}'

        print(f'creating new mon volume {lvm_data_device}')
        run(['lvcreate', '-n', lvm_lv, f'-L{size}', lvm_vg], check=True)
        run([
            'mkfs.xfs', '-L', lvm_lv, '-m', 'crc=1,finobt=1', lvm_data_device],
            check=True)
        run([
            'mount', '-t', 'xfs', '-o', 'defaults,nodev,nosuid',
            'LABEL=ceph-mon', self.mon_dir],
            check=True)

        tmpdir = tempfile.mkdtemp()
        mon_mkfs_args = ['ceph-mon', '-i', self.id, '--mkfs']
        try:
            run(['ceph', 'auth', 'get', f'mon.', '-o', f'{tmpdir}/keyring'],
                check=True)
            mon_mkfs_args += ['--keyring', f'{tmpdir}/keyring']
        except subprocess.CalledProcessError:
            # Looks like we are initializing a new cluster
            config = configparser.ConfigParser()
            with open('/etc/ceph/ceph.conf') as f:
                config.read_file(f)
            fsid = config['global']['fsid']
            mon_mkfs_args += ['--fsid', fsid]
        else:
            run(['ceph', 'mon', 'getmap', '-o', f'{tmpdir}/monmap'],
                check=True)
            mon_mkfs_args += ['--monmap', f'{tmpdir}/monmap']

        run(mon_mkfs_args, check=True)

        shutil.rmtree(tmpdir)

        run(['systemctl', 'start', 'fc-ceph-mon'], check=True)

    def destroy(self):
        try:
            lvm_data_device = find_lv_path('ceph-mon')
        except ValueError:
            lvm_data_device = None

        run(['systemctl', 'stop', 'fc-ceph-mon'], check=True)
        try:
            self.deactivate()
        except Exception:
            pass

        run(['ceph', 'mon', 'remove', self.id])
        run(['umount', self.mon_dir])

        if lvm_data_device:
            run(['wipefs', '-q', '-a', lvm_data_device])
            run(['lvremove', '-f', lvm_data_device])

        os.rmdir(self.mon_dir)
