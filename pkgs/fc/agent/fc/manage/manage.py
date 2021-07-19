"""Update NixOS system configuration from infrastructure or local sources."""

from fc.util.directory import connect
from fc.util.lock import locked
from fc.util.nixos import kernel_version
from .spread import Spread, NullSpread
from subprocess import PIPE, STDOUT
import argparse
import fc.maintenance
import fc.maintenance.lib.shellscript
import filecmp
import io
import json
import logging
import os
import os.path as p
from pathlib import Path
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

# nixos-rebuild doesn't support changing the result link name so we
# create a dir with a meaningful name (like /run/current-system) and
# let nixos-rebuild put it there.
# The link goes away after a reboot. It's possible that the new system
# will be garbage-collected before the switch in that case but the switch
# will still work.
NEXT_SYSTEM = "/run/next-system"

ACTIVATE = f"""\
set -e
nix-channel --add {{url}} nixos
nix-channel --update nixos
nix-channel --remove next
# Retry once in case nixos-build fails e.g. due to updates to Nix itself
nixos-rebuild switch || nixos-rebuild switch
rm -rf {NEXT_SYSTEM}
"""

class ChannelException(Exception):
    pass


class BuildFailed(ChannelException):
    pass


class SwitchFailed(ChannelException):
    pass


class RegisterFailed(ChannelException):
    pass

class DryActivateFailed(ChannelException):
    pass


class Channel:

    PHRASES = re.compile(r'would (\w+) the following units: (.*)$')

    # global, to avoid re-connecting (with ssl handshake and all)
    session = requests.session()
    is_local = False

    def __init__(self, url, name="", environment=None):
        self.url = url
        self.name = name
        self.environment = environment
        self.result_path = None

        if url.startswith("file://"):
            self.is_local = True
            self.resolved_url = url.replace('file://', '')
            return

        if not url.endswith("nixexprs.tar.xz"):
            url = p.join(url, 'nixexprs.tar.xz')

        res = Channel.session.head(url, allow_redirects=True)
        res.raise_for_status()

        self.resolved_url = res.url

    def version(self):
        if self.is_local:
            return "local-checkout"
        label_comp = [
            '/root/.nix-defexpr/channels/{}/{}'.format(self.name, c)
            for c in ['.version', '.version-suffix']]
        if all(p.exists(f) for f in label_comp):
            return ''.join(open(f).read() for f in label_comp)

    def __str__(self):
        v = self.version() or "unknown"
        return '<Channel name={}, version={}, from={}>'.format(
            self.name, v, self.resolved_url)

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

    def switch(self, build_options, lazy=False):
        """
        Build system with this channel and switch to it.
        Replicates the behaviour of nixos-rebuild switch and adds an optional
        lazy mode which only switches to the built system if it actually changed.
        """
        # Put a temporary result link in /run to avoid a race condition
        # with the garbage collector which may remove the system we just built.
        # If register fails, we still hold a GC root until the next reboot.
        out_link = "/run/fc-agent-built-system"
        self.build(build_options, out_link)
        self.register_system_profile()
        # New system is registered, delete the temporary result link.
        os.unlink(out_link)
        self.switch_to_configuration(lazy)

    def build(self, build_options, out_link=None):
        """
        Build system with this channel. Works like nixos-rebuild build.
        Does not modify the running system.
        """
        _log.info('Building %s', self)
        cmd = [
            "nix-build", "--no-build-output",
            "<nixpkgs/nixos>", "-A", "system"
        ]

        if out_link:
            cmd.extend(["--out-link", out_link])
        else:
            cmd.append("--no-out-link")

        if self.is_local:
            self.check_local_channel()
            cmd.extend(['-I', self.resolved_url])
        cmd.extend(build_options)
        _log.debug("Build command is: %s", " ".join(cmd))

        stderr_lines = []
        proc = subprocess.Popen(cmd, stdout=PIPE, stderr=PIPE, text=True)
        while proc.poll() is None:
            line = proc.stderr.readline()
            print(line, end="")
            stderr_lines.append(line)

        if proc.returncode != 0:
            _log.error("Building channel failed!")
            _log.debug("Output from failed build:\n%s", stderr_lines)
            raise BuildFailed()

        result_path = proc.stdout.read().strip()
        _log.debug("Built channel, result is: %s", result_path)
        assert result_path.startswith("/nix/store/"), \
            f"Output doesn't look like a Nix store path: {result_path}"
        self.result_path = result_path

    def switch_to_configuration(self, lazy):
        if self.result_path is None:
            _log.error("This channel hasn't been built yet, cannot switch!")
            return False

        if lazy and p.realpath("/run/current-system") == self.result_path:
            _log.info("Lazy: system config did not change, skipping switch.")
            return False

        _log.info("Switching to system: %s", self.result_path)

        cmd = [f"{self.result_path}/bin/switch-to-configuration", "switch"]
        _log.debug("Switch command is: %s", " ".join(cmd))

        stdout_lines = []
        proc = subprocess.Popen(cmd, stdout=PIPE, stderr=STDOUT, text=True)
        while proc.poll() is None:
            line = proc.stdout.readline()
            print(line, end="")
            stdout_lines.append(line)

        if proc.returncode != 0:
            _log.error("Switch to new system config failed!")
            _log.debug("Output from failed switch:\n%s", stdout_lines)
            raise SwitchFailed()

        return True

    def register_system_profile(self):
        if self.result_path is None:
            _log.error("This channel hasn't been built yet, cannot register!")
            raise RegisterFailed()

        cmd = [
            "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set",
            self.result_path
        ]
        _log.debug("Register command is: %s", " ".join(cmd))

        try:
            subprocess.run(cmd, check=True, stdout=PIPE, stderr=STDOUT, text=True)
        except subprocess.CalledProcessError as e:
            _log.error("Registering the new system in the profile failed:\n%s",
                       e.stdout)
            raise RegisterFailed()

    def prepare_maintenance(self):
        _log.debug('Preparing maintenance')

        if not p.exists(NEXT_SYSTEM):
            os.mkdir(NEXT_SYSTEM)

        cmd = [
            'nixos-rebuild',
            '-I', '/root/.nix-defexpr/channels/next',
            '--no-build-output',
            'dry-activate'
        ]
        _log.debug("Dry-activate (pre-build) command is: %s", " ".join(cmd))

        try:
            call = subprocess.run(
                cmd,
                cwd=NEXT_SYSTEM,
                check=True,
                text=True,
                capture_output=True)
        except subprocess.CalledProcessError as e:
            _log.error("Dry-activate failed, maintenance not registered")
            if e.stdout:
                # Something is wrong with the command itself.
                _log.error("stdout (command error):\n%s", e.stdout)
            if e.stderr:
                # Nix failed (download errors, wrong option values, ...).
                _log.error("stderr (Nix output with errors):\n%s", e.stderr)

            raise DryActivateFailed()

        _log.debug("Nix output from dry activate:\n%s", call.stderr)
        out_link = Path(NEXT_SYSTEM) / "result"
        _log.info("Pre-built system %s", os.readlink(out_link))
        changes = self.detect_changes(call.stderr)
        self.register_maintenance(changes)

    def detect_changes(self, output):
        changes = {}
        for line in output.splitlines():
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
        msg = [
            f'System update to {self.version()}',
            f'Environment: {self.environment}',
            f'Channel URL: {self.resolved_url}'
        ] + notifications

        current_kernel = kernel_version('/run/current-system/kernel')
        next_kernel = kernel_version('/run/next-system/result/kernel')

        if current_kernel != next_kernel:
            msg.append("Will schedule a reboot to activate the changed kernel.")

        if len(msg) > 1:  # add trailing newline if output is multi-line
            msg += ['']

        # XXX: We should use an fc-manage call (like --activate), instead of
        # Dumping the script into the maintenance request.
        script = io.StringIO(ACTIVATE.format(url=self.resolved_url))
        _log.debug("update script:\n%s", script.getvalue())
        _log.debug("message:\n%s", msg)
        with fc.maintenance.ReqManager() as rm:
            rm.add(fc.maintenance.Request(
                fc.maintenance.lib.shellscript.ShellScriptActivity(script),
                600, comment='\n'.join(msg)))


def load_enc(enc_path='/etc/nixos/enc.json'):
    """Tries to read enc.json"""
    global enc
    try:
        with open(enc_path) as f:
            enc = json.load(f)
    except (OSError, ValueError):
        # This environment doesn't seem to support an ENC,
        # i.e. Vagrant. Silently ignore for now.
        enc = {}
        return
    return enc


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


def build_channel_with_maintenance(build_options, spread, lazy):
    if not enc or not enc.get('parameters'):
        _log.warning('No ENC data. Not building channel.')
        return
    # always rebuild current channel (ENC updates, activation scripts etc.)
    build_channel(build_options, spread, lazy, update=False)
    # scheduled update already present?
    if Channel.current('next'):
        rm = fc.maintenance.ReqManager()
        rm.scan()
        if rm.requests:
            _log.info('Channel update prebooked @ %s',
                      list(rm.requests.values())[0].next_due)
            return

    if not spread.is_due():
        return

    # scheduled update available?
    next_channel = Channel(
        enc['parameters']['environment_url'],
        name="next",
        environment=enc['parameters']['environment'])

    if not next_channel or next_channel.is_local:
        _log.error("switch-in-maintenance incompatible with local checkout")
        sys.exit(1)

    current_channel = Channel.current('nixos')
    if next_channel != current_channel:
        next_channel.load('next')
        _log.info('Preparing switch from %s to %s.',
                  current_channel, next_channel)
        try:
            next_channel.prepare_maintenance()
        except DryActivateFailed:
            subprocess.run(["nix-channel", "--remove", "next"], capture_output=True)
            sys.exit(3)
    else:
        _log.info('Current channel is still up-to-date.')


def build_channel(build_options, spread, lazy, update=True):
    if enc and enc.get('parameters'):
        env_name = enc['parameters']['environment']
        _log.info('Environment: %s', env_name)
        channel = Channel(
            enc['parameters']['environment_url'],
            name="nixos",
            environment=env_name)
    else:
        channel = Channel.current('nixos')
    if not channel:
        return
    if update and spread.is_due() and not channel.is_local:
        channel.load('nixos')

    if not channel.is_local:
        channel = Channel.current('nixos')

    if channel:
        try:
            channel.switch(build_options, lazy)
        except ChannelException:
            sys.exit(2)


def build_no_update(build_options, spread, lazy):
    return build_channel(build_options, spread, lazy, update=False)


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
    a.add_argument('-l', '--lazy', default=False, action='store_true',
                   help="only switch to new system if build result changed")
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
        spread = Spread(args.stampfile, args.interval * 60, 'Channel update check')
        spread.configure()
    else:
        spread = NullSpread()

    if args.build:
        globals()[args.build](build_options, spread, args.lazy)

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

    os.environ['NIX_REMOTE'] = 'daemon'

    with locked('/run/lock/fc-manage.lock'):
        transaction(args)


if __name__ == '__main__':
    main()
