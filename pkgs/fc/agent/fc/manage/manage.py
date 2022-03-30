"""Update NixOS system configuration from infrastructure or local sources."""

import argparse
import filecmp
import grp
import hashlib
import io
import json
import os
import os.path as p
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
from datetime import datetime
from functools import partial
from pathlib import Path

import fc.maintenance
import requests
import structlog
from fc.maintenance.lib.shellscript import ShellScriptActivity
from fc.util import nixos
from fc.util.directory import connect
from fc.util.lock import locked
from fc.util.logging import init_logging

from .spread import NullSpread, Spread

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


class Channel:

    PHRASES = re.compile(r"would (\w+) the following units: (.*)$")

    # global, to avoid re-connecting (with ssl handshake and all)
    session = requests.session()
    is_local = False

    def __init__(self, log, url, name="", environment=None, resolve_url=True):
        self.url = url
        self.name = name
        self.environment = environment
        self.system_path = None

        if url.startswith("file://"):
            self.is_local = True
            self.resolved_url = url.replace("file://", "")
        elif resolve_url:
            self.resolved_url = nixos.resolve_url_redirects(url)
        else:
            self.resolved_url = url

        self.log = log

        self.log_with_context = log.bind(
            url=self.resolved_url,
            name=name,
            environment=environment,
            is_local=self.is_local,
        )

    def version(self):
        if self.is_local:
            return "local-checkout"
        label_comp = [
            "/root/.nix-defexpr/channels/{}/{}".format(self.name, c)
            for c in [".version", ".version-suffix"]
        ]
        if all(p.exists(f) for f in label_comp):
            return "".join(open(f).read() for f in label_comp)

    def __str__(self):
        v = self.version() or "unknown"
        return "<Channel name={}, version={}, from={}>".format(
            self.name, v, self.resolved_url
        )

    def __eq__(self, other):
        if isinstance(other, Channel):
            return self.resolved_url == other.resolved_url
        return NotImplemented

    @classmethod
    def current(cls, log, channel_name):
        """Looks up existing channel by name."""
        if not p.exists("/root/.nix-channels"):
            return
        with open("/root/.nix-channels") as f:
            for line in f.readlines():
                url, name = line.strip().split(" ", 1)
                if name == channel_name:
                    return Channel(log, url, name, resolve_url=False)

    def load_nixos(self):
        self.log_with_context.debug("channel-load-nixos")

        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")

        nixos.update_system_channel(self.resolved_url, self.log)

    def load_next(self):
        self.log_with_context.debug("channel-load-next")

        if self.is_local:
            raise RuntimeError("`load` not applicable for local channels")
        subprocess.run(
            ["nix-channel", "--add", self.resolved_url, "next"],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            ["nix-channel", "--update", "next"],
            check=True,
            capture_output=True,
            text=True,
        )

    def check_local_channel(self):
        if not p.exists(p.join(self.resolved_url, "fc")):
            self.log_with_context.error(
                "local-channel-nix-path-invalid",
                _replace_msg="Expected NIX_PATH element 'fc' not found. Did you "
                "create a 'channels' directory via `dev-setup` and point "
                "the channel URL towards that directory?",
            )

    def switch(self, build_options, lazy=False):
        """
        Build system with this channel and switch to it.
        Replicates the behaviour of nixos-rebuild switch and adds an optional
        lazy mode which only switches to the built system if it actually changed.
        """
        self.log_with_context.debug("channel-switch-start")
        # Put a temporary result link in /run to avoid a race condition
        # with the garbage collector which may remove the system we just built.
        # If register fails, we still hold a GC root until the next reboot.
        out_link = "/run/fc-agent-built-system"
        self.build(build_options, out_link)
        nixos.register_system_profile(self.system_path, self.log)
        # New system is registered, delete the temporary result link.
        os.unlink(out_link)
        return nixos.switch_to_system(self.system_path, lazy, self.log)

    def build(self, build_options, out_link=None):
        """
        Build system with this channel. Works like nixos-rebuild build.
        Does not modify the running system.
        """
        self.log_with_context.debug("channel-build-start")

        if self.is_local:
            self.check_local_channel()
        system_path = nixos.build_system(
            self.resolved_url, build_options, out_link, self.log
        )
        self.system_path = system_path

    def prepare_maintenance(self):
        self.log_with_context.debug("channel-prepare-maintenance-start")

        if not p.exists(NEXT_SYSTEM):
            os.mkdir(NEXT_SYSTEM)

        out_link = Path(NEXT_SYSTEM) / "result"
        system_path = nixos.build_system(
            "/root/.nix-defexpr/channels/next", out_link=out_link, log=self.log
        )
        changes = nixos.dry_activate_system(system_path, self.log)
        self.register_maintenance(changes)

    def register_maintenance(self, changes):
        self.log_with_context.debug("maintenance-register-start")

        def notify(category):
            services = changes.get(category, [])
            if services:
                return "{}: {}".format(
                    category.capitalize(),
                    ", ".join(s.replace(".service", "", 1) for s in services),
                )
            else:
                return ""

        notifications = list(
            filter(
                None,
                (notify(cat) for cat in ["stop", "restart", "start", "reload"]),
            )
        )
        msg_parts = [
            f"System update to {self.version()}",
            f"Environment: {self.environment}",
            f"Channel URL: {self.resolved_url}",
        ] + notifications

        current_kernel = nixos.kernel_version("/run/current-system/kernel")
        next_kernel = nixos.kernel_version("/run/next-system/result/kernel")

        if current_kernel != next_kernel:
            self.log.info(
                "maintenance-register-kernel-change",
                current_kernel=current_kernel,
                next_kernel=next_kernel,
            )
            msg_parts.append(
                "Will schedule a reboot to activate the changed kernel."
            )

        if len(msg_parts) > 1:  # add trailing newline if output is multi-line
            msg_parts += [""]

        msg = "\n".join(msg_parts)
        # XXX: We should use an fc-manage call (like --activate), instead of
        # Dumping the script into the maintenance request.
        script = ACTIVATE.format(url=self.resolved_url)
        self.log_with_context.debug(
            "maintenance-register-result", script=script, comment=msg
        )
        with fc.maintenance.ReqManager() as rm:
            rm.add(
                fc.maintenance.Request(
                    ShellScriptActivity(script), 600, comment=msg
                )
            )
        self.log.info("maintenance-register-succeeded")


def load_enc(log, enc_path):
    """Tries to read enc.json"""
    global enc
    try:
        with open(enc_path) as f:
            enc = json.load(f)
    except (OSError, ValueError):
        # This environment doesn't seem to use an ENC,
        # i.e. containers. Silently ignore for now.
        log.info(
            "no-enc-data",
            msg="enc data not supported on this infrastructure, ignoring",
        )
        enc = {}
        return
    return enc


def update_enc_nixos_config(log, enc_path):
    """Update nixos config files managed through the enc."""
    basedir = os.path.join(os.path.dirname(enc_path), "enc-configs")
    if not os.path.isdir(basedir):
        os.makedirs(basedir)
    previous_files = set(os.listdir(basedir))
    sudo_srv = grp.getgrnam("sudo-srv").gr_gid
    for filename, config in enc["parameters"].get("nixos_configs", {}).items():
        log.info(
            "update-enc-nixos-config",
            filename=filename,
            content=hashlib.sha256(config.encode("utf-8")).hexdigest(),
        )
        target = os.path.join(basedir, filename)
        conditional_update(target, config, encode_json=False)
        os.chown(target, -1, sudo_srv)
        previous_files -= {filename}
    for filename in previous_files:
        log.info("remove-stale-enc-nixos-config", filename=filename)
        os.unlink(os.path.join(basedir, filename))


def conditional_update(filename, data, encode_json=True):
    """Updates JSON file on disk only if there is different content."""
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".tmp",
        prefix=p.basename(filename),
        dir=p.dirname(filename),
        delete=False,
    ) as tf:
        if encode_json:
            json.dump(data, tf, ensure_ascii=False, indent=1, sort_keys=True)
        else:
            tf.write(data)
        tf.write("\n")
        os.chmod(tf.fileno(), 0o640)
    if not (p.exists(filename)) or not (filecmp.cmp(filename, tf.name)):
        with open(tf.name, "a") as f:
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
    with open(filename, "r+") as f:
        f.seek(0)
        json.dump(data, f, ensure_ascii=False)
        f.flush()
        f.truncate()
        os.fsync(f.fileno())


def retrieve(log, directory_lookup, tgt):
    log.info("retrieve-enc", _replace_msg="Getting: {tgt}", tgt=tgt)
    try:
        data = directory_lookup()
    except Exception:
        log.error("retrieve-enc-failed", exc_info=True)
        return
    try:
        conditional_update("/etc/nixos/{}".format(tgt), data)
    except (IOError, OSError):
        inplace_update("/etc/nixos/{}".format(tgt), data)


def write_json(log, calls):
    """Writes JSON files from a list of (lambda, filename) pairs."""
    for call in calls:
        retrieve(log, *call)


def system_state(log):
    def load_system_state():
        result = {}
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        _, memkb, _ = line.split()
                        result["memory"] = int(memkb) // 1024
                        break
        except IOError:
            pass
        try:
            with open("/proc/cpuinfo") as f:
                cores = 0
                for line in f:
                    if line.startswith("processor"):
                        cores += 1
            result["cores"] = cores
        except IOError:
            pass
        return result

    write_json(
        log,
        [
            (lambda: load_system_state(), "system_state.json"),
        ],
    )


def update_inventory(log):
    if (
        not enc
        or not enc.get("parameters")
        or not enc["parameters"].get("directory_password")
    ):
        log.warning(
            "update-inventory-no-pass",
            msg="No directory password. Not updating inventory.",
        )
        return
    try:
        # For fc-manage all nodes need to talk about *their* environment which
        # is resource-group specific and requires us to always talk to the
        # ring 1 API.
        directory = connect(enc, 1)
    except socket.error:
        log.warning(
            "update-inventory-no-connection",
            msg="No directory connection. Not updating inventory.",
        )
        return

    log.info(
        "update-inventory",
        _replace_msg="Getting inventory data from directory...",
    )

    write_json(
        log,
        [
            (lambda: directory.lookup_node(enc["name"]), "enc.json"),
            (
                lambda: directory.list_nodes_addresses(
                    enc["parameters"]["location"], "srv"
                ),
                "addresses_srv.json",
            ),
            (lambda: directory.list_permissions(), "permissions.json"),
            (lambda: directory.list_service_clients(), "service_clients.json"),
            (lambda: directory.list_services(), "services.json"),
            (lambda: directory.list_users(), "users.json"),
            (lambda: directory.lookup_resourcegroup("admins"), "admins.json"),
        ],
    )


def prepare_switch_in_maintenance(log, build_options, spread, lazy):
    if not enc or not enc.get("parameters"):
        log.warning(
            "enc-data-missing", msg="No ENC data. Not building channel."
        )
        return
    # always rebuild current channel (ENC updates, activation scripts etc.)
    switch_no_update(log, build_options, spread, lazy)
    # scheduled update already present?
    if Channel.current(log, "next"):
        rm = fc.maintenance.ReqManager()
        rm.scan()
        if rm.requests:
            due = list(rm.requests.values())[0].next_due
            log.info(
                "maintenance-present",
                scheduled=bool(due),
                at=datetime.isoformat(due) if due else None,
            )
            return

    if not spread.is_due():
        return

    # scheduled update available?
    next_channel = Channel(
        log,
        enc["parameters"]["environment_url"],
        name="next",
        environment=enc["parameters"]["environment"],
    )

    if not next_channel or next_channel.is_local:
        log.error(
            "maintenance-error-local-channel",
            _replace_msg="Switch-in-maintenance incompatible with local checkout, abort.",
        )
        sys.exit(1)

    current_channel = Channel.current(log, "nixos")
    if next_channel != current_channel:
        next_channel.load_next()
        log.info(
            "maintenance-prepare-changed",
            current=str(current_channel),
            next=str(next_channel),
        )
        try:
            next_channel.prepare_maintenance()
        except nixos.ChannelException:
            subprocess.run(
                ["nix-channel", "--remove", "next"],
                check=True,
                capture_output=True,
                text=True,
            )
            sys.exit(3)
    else:
        log.info("maintenance-prepare-unchanged")


def switch(log, build_options, spread, lazy, update=True):
    if enc and enc.get("parameters"):
        env_name = enc["parameters"]["environment"]
        log.info(
            "fc-manage-env",
            _replace_msg="Building system with environment {env}.",
            env=env_name,
        )
        channel = Channel(
            log,
            enc["parameters"]["environment_url"],
            name="nixos",
            environment=env_name,
        )
    else:
        channel = Channel.current(log, "nixos")
    if not channel:
        return
    if update:
        if not spread.is_due():
            due = datetime.fromtimestamp(spread.next_due())
            log.info(
                "channel-update-skip-not-due",
                _replace_msg="Next channel update is due at {due}.",
                due=due,
            )
        elif channel.is_local:
            log.info(
                "channel-update-skip-local",
                _replace_msg="Skip channel update because it doesn't make sense with local dev checkouts.",
            )
        else:
            channel.load_nixos()

    if not channel.is_local:
        channel = Channel.current(log, "nixos")

    if channel:
        try:
            return channel.switch(build_options, lazy)
        except nixos.ChannelException:
            sys.exit(2)


def switch_no_update(log, build_options, spread, lazy):
    return switch(log, build_options, spread, lazy, update=False)


def maintenance(log, config_file):
    log.info("maintenance-perform")
    import fc.maintenance.reqmanager

    fc.maintenance.reqmanager.transaction(log=log, config_file=config_file)


def seed_enc(path):
    if os.path.exists(path):
        return
    if not os.path.exists("/tmp/fc-data/enc.json"):
        return
    shutil.move("/tmp/fc-data/enc.json", path)


def exit_timeout(log, signum, frame):
    log.error(
        "exit-timeout",
        msg="Execution timed out. Exiting.",
        signum=signum,
        frame=frame,
    )
    sys.exit(1)


def parse_args():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument(
        "-E",
        "--enc-path",
        default="/etc/nixos/enc.json",
        help="path to enc.json (default: %(default)s)",
    )
    a.add_argument(
        "--fast",
        default=False,
        action="store_true",
        help="instruct nixos-rebuild to perform a fast rebuild",
    )
    a.add_argument(
        "-e",
        "--directory",
        default=False,
        action="store_true",
        help="refresh local ENC copy",
    )
    a.add_argument(
        "-s",
        "--system-state",
        default=False,
        action="store_true",
        help="dump local system information (like memory size) "
        "to system_state.json",
    )
    a.add_argument(
        "-m",
        "--maintenance",
        default=False,
        action="store_true",
        help="run scheduled maintenance",
    )
    a.add_argument(
        "-l",
        "--lazy",
        default=False,
        action="store_true",
        help="only switch to new system if build result changed",
    )
    a.add_argument(
        "-t",
        "--timeout",
        default=3600,
        type=int,
        help="abort execution after <TIMEOUT> seconds",
    )
    a.add_argument(
        "-i",
        "--interval",
        default=120,
        type=int,
        metavar="INT",
        help="automatic mode: channel update every <INT> minutes",
    )
    a.add_argument(
        "-f",
        "--stampfile",
        metavar="PATH",
        default="/var/lib/fc-manage/fc-manage.stamp",
        help="automatic mode: save last execution date to <PATH> "
        "(default: (%(default)s)",
    )
    a.add_argument(
        "-a",
        "--automatic",
        default=False,
        action="store_true",
        help="channel update every I minutes, local builds "
        "all other times (see also -i and -f). Must be used in "
        "conjunction with --channel or --channel-with-maintenance.",
    )
    a.add_argument(
        "--config-file",
        default="/etc/fc-agent.conf",
        help="Config file to use.",
    )

    build = a.add_mutually_exclusive_group()
    build.add_argument(
        "-c",
        "--channel",
        default=False,
        dest="build",
        action="store_const",
        const="switch",
        help="switch machine to FCIO channel",
    )
    build.add_argument(
        "-C",
        "--channel-with-maintenance",
        default=False,
        dest="build",
        action="store_const",
        const="prepare_switch_in_maintenance",
        help="switch machine to FCIO channel during scheduled " "maintenance",
    )
    build.add_argument(
        "-b",
        "--build",
        default=False,
        dest="build",
        action="store_const",
        const="switch_no_update",
        help="rebuild channel or local checkout whatever "
        "is currently active",
    )
    a.add_argument("-v", "--verbose", action="store_true", default=False)

    args = a.parse_args()
    return args


def transaction(log, args):
    seed_enc(args.enc_path)

    keep_cmd_output = False

    build_options = []
    if args.fast:
        build_options.append("--fast")

    load_enc(log, args.enc_path)

    if args.directory:
        update_inventory(log)
        # reload ENC data in case update_inventory changed something
        load_enc(log, args.enc_path)
        update_enc_nixos_config(log, args.enc_path)

    if args.system_state:
        system_state(log)

    if args.automatic:
        spread = Spread(
            args.stampfile, args.interval * 60, "Channel update check"
        )
        spread.configure()
    else:
        spread = NullSpread()

    if args.build:
        keep_cmd_output = globals()[args.build](
            log, build_options, spread, args.lazy
        )

    if args.maintenance:
        maintenance(log, args.config_file)

    return keep_cmd_output


def main():
    args = parse_args()

    # The invocation ID is normally set by systemd when the script is called from a systemd unit.
    invocation_id = os.environ.get("INVOCATION_ID")
    if invocation_id:
        formatted_dt = datetime.now().strftime("%Y-%m-%dT%H_%m_%S")
        cmd_log_file_name = (
            f"/var/log/fc-agent/{formatted_dt}_build-output_{invocation_id}.log"
        )
    else:
        cmd_log_file_name = "/var/log/fc-agent/build-output.log"

    main_log_file = open("/var/log/fc-agent.log", "a")
    cmd_log_file = open(cmd_log_file_name, "w")

    init_logging(args.verbose, main_log_file, cmd_log_file)

    log = structlog.get_logger()

    log.info(
        "fc-manage-start", _replace_msg="fc-manage started with PID: {pid}"
    )

    if args.build:
        log.info(
            "fc-manage-cmd-output",
            _replace_msg="Nix command output goes to: {cmd_log_file}",
            cmd_log_file=cmd_log_file_name,
        )

    signal.signal(signal.SIGALRM, partial(exit_timeout, log))
    signal.alarm(args.timeout)

    os.environ["NIX_REMOTE"] = "daemon"

    with locked(log, "/run/lock", "fc-manage.lock"):
        try:
            keep_cmd_output = transaction(log, args)
        except Exception:
            log.error("fc-manage-unhandled-error", exc_info=True)
            sys.exit(1)

        if invocation_id and args.build and args.lazy and not keep_cmd_output:
            log.info(
                "fc-manage-cmd-output-drop",
                _replace_msg="Remove command logfile because nothing changed.",
            )
            cmd_log_file.close()
            os.unlink(cmd_log_file_name)

    log.info("fc-manage-succeeded")


if __name__ == "__main__":
    main()
