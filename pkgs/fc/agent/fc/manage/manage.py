"""Update NixOS system configuration from infrastructure or local sources."""

from fc.util.directory import connect
from fc.util.lock import locked
from .spread import Spread, NullSpread
import argparse
import fc.maintenance
import fc.maintenance.lib.shellscript
import filecmp
import io
import json
import logging
import os
import os.path as p
import re
import requests
import shutil
import signal
import socket
import subprocess
import sys
import tempfile

_log = logging.getLogger()
enc = {}
spread = NullSpread()

ACTIVATE = """\
set -e
nix-channel --add {url} nixos
nix-channel --update nixos
nixos-rebuild switch
nix-channel --remove next
"""


class Channel:

    PHRASES = re.compile('would (\w+) the following units: (.*)$')

    # global, to avoid re-connecting (with ssl handshake and all)
    session = requests.session()
    is_local = False

    def __init__(self, url, name=None):
        self.url = url
        self.name = name
        if url.startswith("file://"):
            self.is_local = True
            self.resolved_url = url.replace('file://', '')
            return
        self.resolved_url = url.rstrip('/')

    def version(self):
        label_comp = [
            '/root/.nix-defexpr/channels/{}/{}'.format(self.name, c)
            for c in ['.version', '.version-suffix']]
        if all(p.exists(f) for f in label_comp):
            return ''.join(open(f).read() for f in label_comp)

    def __str__(self):
        v = self.version()
        if v:
            return '<Channel {} {}>'.format(self.name, v)
        return '<Channel {} {}>'.format(self.name, self.resolved_url)

    def __eq__(self, other):
        if isinstance(other, Channel):
            return self.resolved_url == other.resolved_url
        return NotImplemented

    @classmethod
    def current(cls, channel_name):
        """Looks up existing channel by name."""
        if not p.exists('/root/.nix-channels'):
            return
        try:
            with open('/root/.nix-channels') as f:
                for line in f.readlines():
                    url, name = line.strip().split(' ', 1)
                    if name == channel_name:
                        return Channel(url, name)
        except OSError:
            _log.exception('Failed to read .nix-channels')
            raise

    def load(self, name):
        """Load channel as given name."""
        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")
        _log.info("Updating channel from %s", self.resolved_url)
        subprocess.check_call(
            ['nix-channel', '--add', self.resolved_url, name])
        subprocess.check_call(['nix-channel', '--update', name])
        self.name = name

    def check_local_channel(self):
        if not p.exists(p.join(self.resolved_url, 'fc')):
            _log.warn(
                "Expected NIX_PATH element 'fc' not found in %s. Did you "
                "create a 'channels' directory via `dev-setup` and point "
                "the channel URL towards that directory?",
                self.resolved_url)

    def switch(self, build_options):
        """Build the "self" channel and switch system to it."""
        _log.info('Building %s', self)
        args = ['nixos-rebuild', '--no-build-output']
        if self.is_local:
            self.check_local_channel()
            args.extend(['-I', self.resolved_url])
        args.extend(['switch'] + build_options)
        subprocess.check_call(args)

    def prepare_maintenance(self):
        _log.debug('Preparing maintenance')
        self.load('next')
        call = subprocess.Popen(
             ['nixos-rebuild',
              '-I', 'nixpkgs=' + '/root/.nix-defexpr/channels/next',
              '--no-build-output',
              'dry-activate'],
             stderr=subprocess.PIPE)
        output = []
        for line in call.stderr.readlines():
            line = line.decode('UTF-8').strip()
            _log.warning(line)
            output.append(line)
        changes = self.detect_changes(output)
        self.register_maintenance(changes)

    def detect_changes(self, output):
        changes = {}
        for line in output:
            m = self.PHRASES.match(line)
            if m is not None:
                action = m.group(1)
                units = [unit.strip() for unit in m.group(2).split(',')]
                changes[action] = units
        return changes

    def register_maintenance(self, changes):
        def notify(category):
            services = changes.get(category, [])
            if services:
                return '{}: {}'.format(
                    category.capitalize(),
                    ', '.join(s.replace('.service', '', 1)
                              for s in services))
            else:
                return ''

        notifications = list(filter(None, (
            notify(cat) for cat in ['stop', 'restart', 'start', 'reload'])))
        msg = ['System update to {}'.format(self)] + notifications
        if len(msg) > 1:  # add trailing newline if output is multi-line
            msg += ['']

        # XXX: We should use an fc-manage call (like --activate), instead of
        # Dumping the script into the maintenance request.
        script = io.StringIO(ACTIVATE.format(url=self.resolved_url))
        with fc.maintenance.ReqManager() as rm:
            rm.add(fc.maintenance.Request(
                fc.maintenance.lib.shellscript.ShellScriptActivity(script),
                300, comment='\n'.join(msg)))


def load_enc(enc_path):
    """Tries to read enc.json"""
    global enc
    try:
        with open(enc_path) as f:
            enc = json.load(f)
    except (OSError, ValueError):
        # This environment doesn't seem to support an ENC,
        # i.e. Vagrant. Silently ignore for now.
        return


def conditional_update(filename, data):
    """Updates JSON file on disk only if there is different content."""
    with tempfile.NamedTemporaryFile(
            mode='w', suffix='.tmp', prefix=p.basename(filename),
            dir=p.dirname(filename), delete=False) as tf:
        json.dump(data, tf, ensure_ascii=False, indent=1, sort_keys=True)
        tf.write('\n')
        os.chmod(tf.fileno(), 0o640)
    if not(p.exists(filename)) or not(filecmp.cmp(filename, tf.name)):
        with open(tf.name, 'a') as f:
            os.fsync(f.fileno())
        os.rename(tf.name, filename)
    else:
        os.unlink(tf.name)


def inplace_update(filename, data):
    """Last-resort JSON update for added robustness.

    If there is no free disk space, `conditional_update` will fail
    because it is not able to create tempfiles. As an emergency measure,
    we fall back to rewriting the file in-place.
    """
    with open(filename, 'r+') as f:
        f.seek(0)
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        f.truncate()
        os.fsync(f.fileno())


def retrieve(directory_lookup, tgt):
    _log.info('Retrieving %s', tgt)
    try:
        data = directory_lookup()
    except Exception:
        _log.exception('Error retrieving data:')
        return
    try:
        conditional_update('/etc/nixos/{}'.format(tgt), data)
    except (IOError, OSError):
        inplace_update('/etc/nixos/{}'.format(tgt), data)


def write_json(calls):
    """Writes JSON files from a list of (lambda, filename) pairs."""
    for call in calls:
        retrieve(*call)


def system_state():
    def load_system_state():
        result = {}
        try:
            with open('/proc/meminfo') as f:
                for line in f:
                    if line.startswith('MemTotal:'):
                        _, memkb, _ = line.split()
                        result['memory'] = int(memkb) // 1024
                        break
        except IOError:
            pass
        try:
            with open('/proc/cpuinfo') as f:
                cores = 0
                for line in f:
                    if line.startswith('processor'):
                        cores += 1
            result['cores'] = cores
        except IOError:
            pass
        return result

    write_json([
        (lambda: load_system_state(), 'system_state.json'),
    ])


def update_inventory():
    if (not enc or not enc.get('parameters') or
            not enc['parameters'].get('directory_password')):
        _log.warning('No directory password. Not updating inventory.')
        return
    try:
        # For fc-manage all nodes need to talk about *their* environment which
        # is resource-group specific and requires us to always talk to the
        # ring 1 API.
        directory = connect(enc, 1)
    except socket.error:
        _log.warning('No directory connection. Not updating inventory.')
        return

    write_json([
        (lambda: directory.lookup_node(enc['name']), 'enc.json'),
        (lambda: directory.list_nodes_addresses(
            enc['parameters']['location'], 'srv'), 'addresses_srv.json'),
        (lambda: directory.list_permissions(), 'permissions.json'),
        (lambda: directory.list_service_clients(), 'service_clients.json'),
        (lambda: directory.list_services(), 'services.json'),
        (lambda: directory.list_users(), 'users.json'),
        (lambda: directory.lookup_resourcegroup('admins'), 'admins.json'),
    ])


def build_channel_with_maintenance(build_options):
    if not enc or not enc.get('parameters'):
        _log.warning('No ENC data. Not building channel.')
        return
    # always rebuild current channel (ENC updates, activation scripts etc.)
    build_channel(build_options, update=False)
    # scheduled update already present?
    if Channel.current('next'):
        rm = fc.maintenance.ReqManager()
        rm.scan()
        if rm.requests:
            _log.info('Channel update prebooked @ %s',
                      list(rm.requests.values())[0].next_due)
            return
    # scheduled update available?
    next_channel = Channel(enc['parameters'].get('environment_url'))
    if not next_channel or next_channel.is_local:
        _log.error("switch-in-maintenance incompatible with local checkout")
        sys.exit(1)
    current_channel = Channel.current('nixos')
    if next_channel != current_channel:
        _log.info('Preparing switch from %s to %s.',
                  current_channel, next_channel)
        next_channel.prepare_maintenance()


def build_channel(build_options, update=True):
    global spread
    try:
        if enc and enc.get('parameters'):
            _log.info('Environment: %s', enc['parameters']['environment'])
            channel = Channel(enc['parameters']['environment_url'])
        else:
            channel = Channel.current('nixos')
        if not channel:
            return
        if update and spread.is_due() and not channel.is_local:
            channel.load('nixos')
        channel.switch(build_options)
    except Exception:
        _log.exception('Error switching channel')
        sys.exit(1)


def build_dev(build_options):
    print("""\
fc-manage -d/--development has been deprecated. Use dev environment instead.

HOWTO:

- Create an environment `dev-$USER` which points to
  `file:///home/$USER/nixpkgs` (or similar).
- Switch node to `dev-$USER` in directory.
- rsync nixpkgs to location mentioned in environment.
- Run `fc-manage -b -e`.

Note: there is no need to switch off `flyingcircus.agent.enable`.""")


def build_no_update(build_options):
    return build_channel(build_options, update=False)


def maintenance():
    _log.info('Performing scheduled maintenance')
    import fc.maintenance.reqmanager
    fc.maintenance.reqmanager.transaction()


def seed_enc(path):
    if os.path.exists(path):
        return
    if not os.path.exists('/tmp/fc-data/enc.json'):
        return
    shutil.move('/tmp/fc-data/enc.json', path)


def exit_timeout(signum, frame):
    _log.error("Execution timed out. Exiting.")
    sys.exit(1)


def parse_args():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument('-E', '--enc-path', default='/etc/nixos/enc.json',
                   help='path to enc.json (default: %(default)s)')
    a.add_argument('--show-trace', default=False, action='store_true',
                   help='instruct nixos-rebuild to dump tracebacks on failure')
    a.add_argument('--fast', default=False, action='store_true',
                   help='instruct nixos-rebuild to perform a fast rebuild')
    a.add_argument('-e', '--directory', default=False, action='store_true',
                   help='refresh local ENC copy')
    a.add_argument('-s', '--system-state', default=False, action='store_true',
                   help='dump local system information (like memory size) '
                   'to system_state.json')
    a.add_argument('-m', '--maintenance', default=False, action='store_true',
                   help='run scheduled maintenance')
    a.add_argument('-t', '--timeout', default=3600, type=int,
                   help='abort execution after <TIMEOUT> seconds')
    a.add_argument('-i', '--interval', default=120, type=int, metavar='INT',
                   help='automatic mode: channel update every <INT> minutes')
    a.add_argument('-f', '--stampfile', metavar='PATH',
                   default='/var/lib/fc-manage/fc-manage.stamp',
                   help='automatic mode: save last execution date to <PATH> '
                   '(default: (%(default)s)')
    a.add_argument('-a', '--automatic', default=False, action='store_true',
                   help='channel update every I minutes, local builds '
                   'all other times (see also -i and -f). Must be used in '
                   'conjunction with --channel or --channel-with-maintenance.')

    build = a.add_mutually_exclusive_group()
    build.add_argument('-c', '--channel', default=False, dest='build',
                       action='store_const', const='build_channel',
                       help='switch machine to FCIO channel')
    build.add_argument('-C', '--channel-with-maintenance', default=False,
                       dest='build', action='store_const',
                       const='build_channel_with_maintenance',
                       help='switch machine to FCIO channel during scheduled '
                       'maintenance')
    build.add_argument('-d', '--development', default=False, dest='build',
                       action='store_const', const='build_dev',
                       help='(deprecated, use dev-* environment)')
    build.add_argument('-b', '--build', default=False, dest='build',
                       action='store_const', const='build_no_update',
                       help='rebuild channel or local checkout whatever '
                       'is currently active')
    a.add_argument('-v', '--verbose', action='store_true', default=False)

    args = a.parse_args()
    return args


def transaction(args):
    seed_enc(args.enc_path)

    build_options = []
    if args.show_trace:
        build_options.append('--show-trace')
    if args.fast:
        build_options.append('--fast')

    if args.directory:
        load_enc(args.enc_path)
        update_inventory()

    if args.system_state:
        system_state()

    # reload ENC data in case update_inventory changed something
    load_enc(args.enc_path)

    if args.automatic:
        global spread
        spread = Spread(args.stampfile, args.interval * 60, 'Channel update')
        spread.configure()

    if args.build:
        globals()[args.build](build_options)

    if args.maintenance:
        maintenance()


def main():
    args = parse_args()
    signal.signal(signal.SIGALRM, exit_timeout)
    signal.alarm(args.timeout)

    logging.basicConfig(format='%(levelname)s: %(message)s',
                        level=logging.DEBUG if args.verbose else logging.INFO)
    # this is really annoying
    logging.getLogger('iso8601').setLevel(logging.WARNING)
    logging.getLogger('requests').setLevel(logging.WARNING)

    with locked('/run/lock/fc-manage.lock'):
        transaction(args)


if __name__ == '__main__':
    main()
