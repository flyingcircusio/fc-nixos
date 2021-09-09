"""Helpers for interaction with the NixOS system"""

from pathlib import Path
from subprocess import PIPE, STDOUT
import json
import os
import os.path as p
import re
import requests
import structlog
import subprocess

_log = structlog.get_logger()

requests_session = requests.session()

PHRASES = re.compile(r'would (\w+) the following units: (.*)$')
FC_ENV_FILE = "/etc/fcio_environment"


class Channel:

    def __init__(self, url) -> None:
        self.url = url


class ChannelException(Exception):
    pass


class ChannelUpdateFailed(ChannelException):
    pass


class BuildFailed(ChannelException):
    pass


class SwitchFailed(ChannelException):
    pass


class RegisterFailed(ChannelException):
    pass


class DryActivateFailed(ChannelException):
    pass


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
        raise RuntimeError(
            'modules subdir does not contain exactly '
            'one item', moddir)
    return moddir[0]


def current_fc_environment_name(log=_log):
    env_path = Path(FC_ENV_FILE)
    if env_path.exists():
        environment = env_path.read_text()
        log.debug("fc-environment", env=environment)
        return environment
    else:
        log.debug("fc-environment-env-file-missing", filename=FC_ENV_FILE)


def channel_version(channel_url, log=_log):
    log.debug("channel_version", channel=channel_url)
    final_channel_url = resolve_url_redirects(channel_url)
    try:
        nixpkgs_path = subprocess.run(
            ["nix-instantiate", "-I", final_channel_url, "--find-file", "."],
            check=True,
            capture_output=True,
            text=True).stdout.strip()
    except subprocess.CalledProcessError as e:
        log.error(
            "channel-version-failed",
            msg="getting version file from channel failed",
            stderr=e.stderr)
        raise

    version = Path(nixpkgs_path, ".version").read_text()
    suffix = Path(nixpkgs_path, ".version-suffix").read_text()

    return version + suffix


def running_system_version():
    version_json = subprocess.run(["nixos-version", "--json"],
                                  check=True,
                                  capture_output=True,
                                  text=True).stdout

    return json.loads(version_json)["nixosVersion"]


def current_nixos_channel_version():
    is_local = False
    if is_local:
        return "local-checkout"

    label_comp = [
        '/root/.nix-defexpr/channels/nixos/{}'.format(c)
        for c in ['.version', '.version-suffix']
    ]

    return ''.join(open(f).read() for f in label_comp)


def current_nixos_channel_url(log=_log):
    if not p.exists('/root/.nix-channels'):
        log.warn(
            "nix-channel-file-missing",
            _replace_msg="/root/.nix-channels does not exist, doing nothing")
        return
    try:
        with open('/root/.nix-channels') as f:
            for line in f.readlines():
                url, name = line.strip().split(' ', 1)
                if name == "nixos":
                    log.debug("nixos-channel-found", channel=url)
                    return url
    except OSError:
        log.error(
            "nix-channel-file-error",
            "Failed to read .nix-channels. See exception for details.",
            exc_info=True)


def resolve_url_redirects(url):
    if not url.endswith("nixexprs.tar.xz"):
        url = p.join(url, 'nixexprs.tar.xz')

    res = requests_session.head(url, allow_redirects=True)
    res.raise_for_status()

    return res.url


def detect_systemd_unit_changes(dry_activate_lines):
    changes = {}
    for line in dry_activate_lines:
        m = PHRASES.match(line)
        if m is not None:
            action = m.group(1)
            units = [unit.strip() for unit in m.group(2).split(',')]
            changes[action] = units
    return changes


def update_system_channel(channel_url, log=_log):
    """Update nixos channel URL if changed and fetch new contents.
    """
    current_channel_url = current_nixos_channel_url(log)

    if current_channel_url == channel_url:
        log.debug("system-channel-url-unchanged")
    else:
        log.info(
            "system-channel-url-changed",
            _replace_msg=
            "System channel URL changed from {current_channel_url} to {new_channel_url}",
            current_channel_url=current_channel_url,
            new_channel_url=channel_url)
        subprocess.run(['nix-channel', '--add', channel_url, "nixos"],
                       check=True,
                       capture_output=True,
                       text=True)

    stdout_lines = []
    proc = subprocess.Popen(['nix-channel', '--update', "nixos"],
                            stdout=PIPE,
                            stderr=PIPE,
                            text=True)
    log.info(
        "system-channel-update-started",
        _replace_msg="Channel update command started with PID: {cmd_pid}",
        cmd_pid=proc.pid)
    while proc.poll() is None:
        line = proc.stdout.readline()
        log.trace(
            "system-channel-update-out", cmd_output_line=line.strip("\n"))
        stdout_lines.append(line)

    stdout = "".join(stdout_lines)

    if proc.returncode == 0:
        log.debug("system-channel-update-succeeded")
    else:
        log.error(
            "system-channel-update-failed",
            _replace_msg=
            "System channel update failed, see command output for details.",
            stdout=stdout,
            stderr=proc.stderr.read())
        raise ChannelUpdateFailed()


def switch_to_channel(channel_url, lazy=False, log=_log):
    final_channel_url = resolve_url_redirects(channel_url)
    """
    Build system with this channel and switch to it.
    Replicates the behaviour of nixos-rebuild switch and adds an optional
    lazy mode which only switches to the built system if it actually changed.
    """
    log.info(
        "channel-switch",
        channel=channel_url,
        resolved_channel=final_channel_url)
    # Put a temporary result link in /run to avoid a race condition
    # with the garbage collector which may remove the system we just built.
    # If register fails, we still hold a GC root until the next reboot.
    out_link = "/run/fc-agent-built-system"
    built_system = build_system(final_channel_url, out_link)
    register_system_profile(built_system)
    # New system is registered, delete the temporary result link.
    os.unlink(out_link)
    return switch_to_system(built_system, lazy)


def build_system(channel_url, build_options=None, out_link=None, log=_log):
    """
    Build system with this channel. Works like nixos-rebuild build.
    Does not modify the running system.
    """
    log.debug('system-build-start', channel=channel_url)
    cmd = [
        "nix-build", "--no-build-output", "--show-trace", "-I", channel_url,
        "<nixpkgs/nixos>", "-A", "system"
    ]

    if out_link:
        cmd.extend(["--out-link", str(out_link)])
    else:
        cmd.append("--no-out-link")

    if build_options is not None:
        cmd.extend(build_options)

    log.debug("system-build-command", cmd=" ".join(cmd))

    stderr_lines = []
    proc = subprocess.Popen(cmd, stdout=PIPE, stderr=PIPE, text=True)
    log.info(
        "system-build-started",
        _replace_msg="Nix build command started with PID: {cmd_pid}",
        cmd_pid=proc.pid)
    while proc.poll() is None:
        line = proc.stderr.readline()
        log.trace("system-build-out", cmd_output_line=line.strip("\n"))
        stderr_lines.append(line)

    stderr = "".join(stderr_lines).strip()

    if stderr:
        changed = True
    else:
        stderr = None
        changed = False

    if proc.returncode == 0:
        if changed:
            msg = "Successfully built new system."
        else:
            msg = "Built system, no changes."
        log.info(
            "system-build-succeeded",
            _replace_msg=msg,
            changed=changed,
            build_output=stderr)
    else:
        log.error(
            "system-build-failed",
            _replace_msg="Building the system failed!",
            stdout=proc.stdout.read().strip() or None,
            stderr=stderr)
        raise BuildFailed()

    system_path = proc.stdout.read().strip()
    log.debug("system-build-finished", system=system_path)
    assert system_path.startswith("/nix/store/"), \
        f"Output doesn't look like a Nix store path: {system_path}"

    return system_path


def switch_to_system(system_path, lazy, log=_log):
    if lazy and p.realpath("/run/current-system") == system_path:
        log.info(
            "system-switch-skip",
            _replace_msg="Lazy: system config did not change, skipping switch.",
            system=system_path)
        return False

    log.info(
        "system-switch-start",
        _replace_msg="Switching to new system configuration: {system}",
        system=system_path)

    cmd = [f"{system_path}/bin/switch-to-configuration", "switch"]

    log.debug("system-switch-command", cmd=" ".join(cmd))

    stdout_lines = []
    proc = subprocess.Popen(cmd, stdout=PIPE, stderr=STDOUT, text=True)
    log.info(
        "system-switch-started",
        _replace_msg="Switch command started with PID: {cmd_pid}",
        cmd_pid=proc.pid)
    while proc.poll() is None:
        line = proc.stdout.readline()
        log.trace("system-switch-out", cmd_output_line=line.strip("\n"))
        stdout_lines.append(line)

    stdout = "".join(stdout_lines)

    if proc.returncode == 0:
        log.info(
            "system-switch-succeeded",
            _replace_msg="Completed switch to new system configuration.",
            switch_output=stdout,
            system=system_path)
    else:
        log.error(
            "system-switch-failed",
            _replace_msg="Switching to new system failed!",
            stdout=stdout,
            system_path=system_path)
        raise SwitchFailed()

    return True


def dry_activate_system(system_path, log=_log):
    cmd = [f"{system_path}/bin/switch-to-configuration", "dry-activate"]
    log.info("system-dry-activate-start", system=system_path)
    log.debug("system-dry-activate-cmd", cmd=" ".join(cmd))

    stdout_lines = []
    proc = subprocess.Popen(cmd, stdout=PIPE, stderr=STDOUT, text=True)
    while proc.poll() is None:
        line = proc.stdout.readline()
        log.trace("system-dry-activate-out", cmd_output_line=line.strip())
        stdout_lines.append(line)

    if proc.returncode != 0:
        log.error(
            "system-dry-activate-failed",
            msg="Dry-activating the new system failed!",
            stdout="\n".join(stdout_lines))
        raise DryActivateFailed()

    return detect_systemd_unit_changes(stdout_lines)


def register_system_profile(system_path, log=_log):
    cmd = [
        "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set",
        system_path
    ]
    log.debug("register-system-profile-command", cmd=" ".join(cmd))

    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        log.error(
            "register-system-profile-failed",
            _replace_msg="Registering the new system in the profile failed!",
            stdout=e.stdout,
            stderr=e.stderr)
        raise RegisterFailed()
