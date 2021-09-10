import pytest
import shlex
from fc.util import nixos
from unittest import mock
import structlog
import textwrap

structlog.configure(wrapper_class=structlog.BoundLogger)


class FakeCmdStream:

    def __init__(self, content):
        self.content = content
        self.line_gen = (l for l in content.splitlines(keepends=True))
        self.finished = False

    def read_next(self):
        try:
            self.next_line = next(self.line_gen)
        except StopIteration:
            self.finished = True

    def readline(self):
        return self.next_line

    def read(self):
        return self.content


class PollingFakePopen:

    def __init__(self,
                 cmd,
                 stdout='',
                 stderr='',
                 poll='stdout',
                 returncode=0,
                 pid=123):
        self.cmd = cmd
        self.stdout = FakeCmdStream(stdout)
        self.stderr = FakeCmdStream(stderr)
        self.returncode = returncode
        self.pid = pid
        self._poll = poll

    def poll(self):
        if self._poll == 'stdout':
            self.stdout.read_next()
            if self.stdout.finished:
                return self.returncode

        if self._poll == 'stderr':
            self.stderr.read_next()
            if self.stderr.finished:
                return self.returncode


def test_build_system_with_changes(log, monkeypatch):
    channel = "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = textwrap.dedent("""
        these derivations will be built:
        /nix/store/0yrw0jdjrwfkjdpxqf3rbd902c6waxim-system-path.drv
        /nix/store/a69b25l5y6pgbb9r71fa0c4lhrhjsj85-nixos-system-test55-21.05pre-git.drv
        building '/nix/store/0yrw0jdjrwfkjdpxqf3rbd902c6waxim-system-path.drv'...
        building '/nix/store/a69b25l5y6pgbb9r71fa0c4lhrhjsj85-nixos-system-test55-21.05pre-git.drv'...
    """)

    cmd = shlex.split(
        f"nix-build --no-build-output --show-trace -I {channel} <nixpkgs/nixos> -A system --out-link /run/fc-agent-test -v"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll='stderr')

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    built_system_path = nixos.build_system(
        channel, build_options=["-v"], out_link="/run/fc-agent-test")

    popen_mock.assert_called_once_with(cmd, stdout=-1, stderr=-1, text=True)
    assert built_system_path == system_path
    assert log.has(
        "system-build-succeeded",
        changed=True,
        build_output=build_output.strip())


def test_build_system_unchanged(log, monkeypatch):
    channel = "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = "\n"

    cmd = shlex.split(
        f"nix-build --no-build-output --show-trace -I {channel} <nixpkgs/nixos> -A system --no-out-link"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll='stderr')

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    built_system_path = nixos.build_system(channel)

    assert built_system_path == system_path
    popen_mock.assert_called_once_with(cmd, stdout=-1, stderr=-1, text=True)
    assert log.has("system-build-succeeded", changed=False)


def test_build_system_fail(log, monkeypatch):
    channel = "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = textwrap.dedent("""
        error: The option `wrongOption' does not exist. Definition values:
        - In `/etc/local/nixos/dev_vm.nix': true
        (use '--show-trace' to show detailed location information)
    """)

    cmd = shlex.split(
        f"nix-build --no-build-output -I {channel} <nixpkgs/nixos> -A system --no-out-link"
    )

    nix_build_fake = PollingFakePopen(
        cmd,
        stdout=system_path,
        stderr=build_output,
        poll='stderr',
        returncode=1)

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    with pytest.raises(nixos.BuildFailed):
        nixos.build_system(channel)

    assert log.has("system-build-failed", stderr=build_output.strip())


def test_switch_to_system(log, monkeypatch):
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    switch_output = textwrap.dedent("""
        updating GRUB 2 menu...
        activating the configuration...
        setting up /etc...
        reloading user units for ts...
        setting up tmpfiles
        reloading the following units: dbus.service
        restarting the following units: polkit.service
    """)

    cmd = shlex.split(f"{system_path}/bin/switch_to_system")

    switch_fake = PollingFakePopen(
        cmd, stdout=switch_output, poll='stdout', returncode=0)

    popen_mock = mock.Mock(return_value=switch_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)
    monkeypatch.setattr("os.path.realpath", lambda p: "other")

    changed = nixos.switch_to_system(system_path, lazy=True)
    assert changed


def test_switch_to_system_lazy_unchanged(log, monkeypatch):
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    monkeypatch.setattr("os.path.realpath", lambda p: system_path)

    changed = nixos.switch_to_system(system_path, lazy=True)
    assert not changed
    assert log.has("system-switch-skip")


def test_update_nixos_channel(monkeypatch):
    current_channel = "https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz"
    monkeypatch.setattr("fc.util.nixos.current_nixos_channel_url",
                        (lambda: current_channel))



def test_find_nix_build_error_missing_option():

    stderr = textwrap.dedent("""\
    error: while evaluating the attribute 'config.system.build.toplevel' at /home/test/fc-nixos/channels/nixpkgs/nixos/modules/system/activation/top-level.nix:293:5:
    while evaluating 'merge' at /home/test/fc-nixos/channels/nixpkgs/lib/types.nix:512:22, called from /home/test/fc-nixos/channels/nixpkgs/lib/modules.nix:559:59:
    while evaluating 'evalModules' at /home/test/fc-nixos/channels/nixpkgs/lib/modules.nix:62:17, called from /home/test/fc-nixos/channels/nixpkgs/lib/types.nix:513:12:
    The option `flyingcircus.services.nginx.virtualHosts.test55.forcSSL' does not exist. Definition values:
    - In `/home/test/fc-nixos/channels/fc/nixos/services/nginx': true
    """)
    expected = "The option `flyingcircus.services.nginx.virtualHosts.test55.forcSSL' does not exist."
    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_default_when_no_error_message():

    stderr = textwrap.dedent("""\
    error: while evaluating the attribute 'config.system.build.toplevel' at /home/test/fc-nixos/channels/nixpkgs/nixos/modules/system/activation/top-level.nix:293:5:
    while evaluating 'merge' at /home/test/fc-nixos/channels/nixpkgs/lib/types.nix:512:22, called from /home/test/fc-nixos/channels/nixpkgs/lib/modules.nix:559:59:
    """)
    assert nixos.find_nix_build_error(stderr) == "Building the system failed!"


def test_find_nix_build_error_syntax():

    stderr = textwrap.dedent("""\
    error: while evaluating the attribute 'config.system.build.toplevel' at /home/ts/fc-nixos/channels/nixpkgs/nixos/lib/eval-config.nix:64:5:
    while evaluating 'applyIfFunction' at /home/ts/fc-nixos/channels/nixpkgs/lib/modules.nix:288:29, called from /home/ts/fc-nixos/channels/nixpkgs/lib/modules.nix:195:59:
    while evaluating 'isFunction' at /home/ts/fc-nixos/channels/nixpkgs/lib/trivial.nix:345:16, called from /home/ts/fc-nixos/channels/nixpkgs/lib/modules.nix:288:68:
    syntax error, unexpected '}', expecting ';', at /etc/local/nixos/dev_vm.nix:190:1
    """)
    expected = "syntax error, unexpected '}', expecting ';', at /etc/local/nixos/dev_vm.nix:190:1"
    assert nixos.find_nix_build_error(stderr) == expected
