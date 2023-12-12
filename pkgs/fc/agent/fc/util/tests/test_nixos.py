import shlex
import textwrap
from unittest import mock

import pytest
import structlog
from fc.util import nixos
from fc.util.tests import PollingFakePopen

structlog.configure(wrapper_class=structlog.BoundLogger)

FC_CHANNEL = (
    "https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz"
)


def test_get_fc_channel_build(log):
    build = nixos.get_fc_channel_build(FC_CHANNEL)
    assert build == "93111"


def test_get_fc_channel_build_should_warn_for_non_fc_channel(log):
    invalid_channel = "http://invalid"
    build = nixos.get_fc_channel_build(invalid_channel)
    assert build is None
    log.has("no-fc-channel-url", channel_url=invalid_channel)


def test_build_system_with_changes(log, monkeypatch):
    channel = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = textwrap.dedent(
        """
        these derivations will be built:
        /nix/store/0yrw0jdjrwfkjdpxqf3rbd902c6waxim-system-path.drv
        /nix/store/a69b25l5y6pgbb9r71fa0c4lhrhjsj85-nixos-system-test55-21.05pre-git.drv
        building '/nix/store/0yrw0jdjrwfkjdpxqf3rbd902c6waxim-system-path.drv'...
        building '/nix/store/a69b25l5y6pgbb9r71fa0c4lhrhjsj85-nixos-system-test55-21.05pre-git.drv'...
    """
    )

    cmd = shlex.split(
        f"nix-build --no-build-output <nixpkgs/nixos> -A system -I {channel} --out-link /run/fc-agent-test -v"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll="stderr"
    )

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    built_system_path = nixos.build_system(
        channel, build_options=["-v"], out_link="/run/fc-agent-test"
    )

    popen_mock.assert_called_once_with(cmd, stdout=-1, stderr=-1, text=True)
    assert built_system_path == system_path
    assert log.has(
        "system-build-succeeded",
        changed=True,
        build_output=build_output.strip(),
    )


def test_build_system_unchanged(log, monkeypatch):
    channel = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = "\n"

    cmd = shlex.split(
        f"nix-build --no-build-output <nixpkgs/nixos> -A system -I {channel} --no-out-link"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll="stderr"
    )

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    built_system_path = nixos.build_system(channel)

    assert built_system_path == system_path
    popen_mock.assert_called_once_with(cmd, stdout=-1, stderr=-1, text=True)
    assert log.has("system-build-succeeded", changed=False)


def test_build_system_fail(log, monkeypatch):
    channel = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = textwrap.dedent(
        """
        error: The option `wrongOption' does not exist. Definition values:
        - In `/etc/local/nixos/dev_vm.nix': true
        (use '--show-trace' to show detailed location information)
    """
    )

    cmd = shlex.split(
        f"nix-build --no-build-output -I {channel} <nixpkgs/nixos> -A system --no-out-link"
    )

    nix_build_fake = PollingFakePopen(
        cmd,
        stdout=system_path,
        stderr=build_output,
        poll="stderr",
        returncode=1,
    )

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)

    with pytest.raises(nixos.BuildFailed):
        nixos.build_system(channel)

    assert log.has("system-build-failed", stderr=build_output.strip())


def test_switch_to_system(log, monkeypatch):
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    switch_output = textwrap.dedent(
        """
        updating GRUB 2 menu...
        activating the configuration...
        setting up /etc...
        reloading user units for ts...
        setting up tmpfiles
        reloading the following units: dbus.service
        restarting the following units: polkit.service
    """
    )

    cmd = shlex.split(f"{system_path}/bin/switch_to_system")

    switch_fake = PollingFakePopen(
        cmd, stdout=switch_output, poll="stdout", returncode=0
    )

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


def test_update_system_channel(log, monkeypatch):
    current_channel = FC_CHANNEL
    next_channel = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )

    monkeypatch.setattr(
        "fc.util.nixos.current_nixos_channel_url", (lambda _: current_channel)
    )
    channel_update_fake = PollingFakePopen(
        "nix-channel --update nixos", stdout="", poll="stdout", returncode=0
    )

    popen_mock = mock.Mock(return_value=channel_update_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)
    run_mock = mock.Mock()
    monkeypatch.setattr("subprocess.run", run_mock)

    nixos.update_system_channel(next_channel)

    run_mock.assert_called_once()
    assert run_mock.call_args[0][0] == [
        "nix-channel",
        "--add",
        next_channel,
        "nixos",
    ]


def test_find_nix_build_error_missing_option():
    stderr = textwrap.dedent(
        """
        trace: [ "environment" ]
        trace: Obsolete option `flyingcircus.roles.statshost.enable' is used. It was renamed to `flyingcircus.roles.statshost-global.enable'.
        error:
               … while calling the 'head' builtin

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/attrsets.nix:850:11:

                  849|         || pred here (elemAt values 1) (head values) then
                  850|           head values
                     |           ^
                  851|         else

               … while evaluating the attribute 'value'

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:807:9:

                  806|     in warnDeprecation opt //
                  807|       { value = builtins.addErrorContext "while evaluating the option `${showOption loc}':" value;
                     |         ^
                  808|         inherit (res.defsFinal') highestPrio;

               (stack trace truncated; use '--show-trace' to show the full trace)

               error: The option `services.nginx.virtualHosts."test66.fe.rzob.fcio.net".forcSSL' does not exist. Definition values:
               - In `/etc/local/nixos/dev_vm.nix': true
        """
    )
    expected = textwrap.dedent(
        """
        The option `services.nginx.virtualHosts."test66.fe.rzob.fcio.net".forcSSL' does not exist. Definition values:
        - In `/etc/local/nixos/dev_vm.nix': true
        """
    ).strip()
    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_default_when_no_error_message():
    stderr = "weird error nobody expects"
    assert nixos.find_nix_build_error(stderr) == "Building the system failed!"


def test_find_nix_build_error_syntax():
    stderr = textwrap.dedent(
        """
        error:
               … while evaluating the attribute 'config.system.build.toplevel'

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:320:9:

                  319|         options = checked options;
                  320|         config = checked (removeAttrs config [ "_module" ]);
                     |         ^
                  321|         _module = checked (config._module);

               … while calling the 'seq' builtin

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:320:18:

                  319|         options = checked options;
                  320|         config = checked (removeAttrs config [ "_module" ]);
                     |                  ^
                  321|         _module = checked (config._module);

               (stack trace truncated; use '--show-trace' to show the full trace)

               error: syntax error, unexpected ';'

               at /etc/local/nixos/dev_vm.nix:190:1:

                  189| #flyingcircus.roles.k3s-server.enable = lib.mkForce true
                  190| ;
                     | ^
                  191|
        """
    )
    expected = textwrap.dedent(
        """
        syntax error, unexpected ';'
        at /etc/local/nixos/dev_vm.nix:190:1:
        """
    ).strip()
    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_builder_failed():
    stderr = textwrap.dedent(
        """
        building '/nix/store/hv6cll5bd85bz6jid7zjvrajwn72sm3b-python3.10-fc-agent-1.0.drv'...
        error: builder for '/nix/store/4jii0wdji3s5qp6pknkg9ljnngrrcxk8-fail.drv' failed with exit code 127;
               last 1 log lines:
               > /build/.attr-0l2nkwhif96f51f4amnlf414lhl4rv9vh8iffyp431v6s28gsr90: line 1: fail: command not found
               For full logs, run 'nix log /nix/store/4jii0wdji3s5qp6pknkg9ljnngrrcxk8-fail.drv'.
        error: 1 dependencies of derivation '/nix/store/wjdn47b0930pi0pidmyp8y04fqcj1zp9-system-path.drv' failed to build
        error: 1 dependencies of derivation '/nix/store/v8yhhp9psq9hpi7sp9v2j8si7nl1bc0k-nixos-system-test66-22.11pre-git.drv' failed to build
        """
    )

    expected = "builder for '/nix/store/4jii0wdji3s5qp6pknkg9ljnngrrcxk8-fail.drv' failed with exit code 127"
    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_type_error():
    stderr = textwrap.dedent(
        """
        building '/nix/store/my39ycs0z8xcx3ih78xb3j39r2mz5x88-firewall-local-rules.drv'...
        error:
               … while calling the 'head' builtin

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/attrsets.nix:850:11:

                  849|         || pred here (elemAt values 1) (head values) then
                  850|           head values
                     |           ^
                  851|         else

               … while evaluating the attribute 'value'

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:807:9:

                  806|     in warnDeprecation opt //
                  807|       { value = builtins.addErrorContext "while evaluating the option `${showOption loc}':" value;
                     |         ^
                  808|         inherit (res.defsFinal') highestPrio;

               (stack trace truncated; use '--show-trace' to show the full trace)

               error: value is a string while a set was expected
        """
    )

    expected = textwrap.dedent(
        """
        value is a string while a set was expected
        """
    ).strip()
    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_conflicting_values():
    stderr = textwrap.dedent(
        """
        trace: [ "environment" ]
        trace: Obsolete option `flyingcircus.roles.statshost.enable' is used. It was renamed to `flyingcircus.roles.statshost-global.enable'.
        trace: warning: The type `types.string` is deprecated. See https://github.com/NixOS/nixpkgs/pull/66346 for better alternative types.
        error:
               … while calling the 'head' builtin

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/attrsets.nix:850:11:

                  849|         || pred here (elemAt values 1) (head values) then
                  850|           head values
                     |           ^
                  851|         else

               … while evaluating the attribute 'value'

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:807:9:

                  806|     in warnDeprecation opt //
                  807|       { value = builtins.addErrorContext "while evaluating the option `${showOption loc}':" value;
                     |         ^
                  808|         inherit (res.defsFinal') highestPrio;

               (stack trace truncated; use '--show-trace' to show the full trace)

               error: The option `security.dhparams.enable' has conflicting definition values:
               - In `/etc/local/nixos/dev_vm.nix': false
               - In `/nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/fc/nixos/platform': true
               Use `lib.mkForce value` or `lib.mkDefault value` to change the priority on any of these definitions.
        """
    )
    expected = textwrap.dedent(
        """
        The option `security.dhparams.enable' has conflicting definition values:
        - In `/etc/local/nixos/dev_vm.nix': false
        - In `/nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/fc/nixos/platform': true
        """
    ).strip()

    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_failed_assertion():
    stderr = textwrap.dedent(
        """
        trace: [ "environment" ]
        trace: Obsolete option `flyingcircus.roles.statshost.enable' is used. It was renamed to `flyingcircus.roles.statshost-global.enable'.
        trace: warning: The type `types.string` is deprecated. See https://github.com/NixOS/nixpkgs/pull/66346 for better alternative types.
        error:
               … while calling the 'head' builtin

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/attrsets.nix:850:11:

                  849|         || pred here (elemAt values 1) (head values) then
                  850|           head values
                     |           ^
                  851|         else

               … while evaluating the attribute 'value'

                 at /nix/store/1hfsxsfgx9pzxx5mijz3n5rmvpfq7adj-source/nixpkgs/lib/modules.nix:807:9:

                  806|     in warnDeprecation opt //
                  807|       { value = builtins.addErrorContext "while evaluating the option `${showOption loc}':" value;
                     |         ^
                  808|         inherit (res.defsFinal') highestPrio;

               (stack trace truncated; use '--show-trace' to show the full trace)

               error:
               Failed assertions:
               - The option definition `flyingcircus.roles.loghost.enable' in `/etc/local/nixos/dev_vm.nix' no longer has any effect; please remove it.
               Last platform version that supported graylog/loghost was 22.05.
        """
    )
    expected = textwrap.dedent(
        """
        Failed assertions:
        - The option definition `flyingcircus.roles.loghost.enable' in `/etc/local/nixos/dev_vm.nix' no longer has any effect; please remove it.
        Last platform version that supported graylog/loghost was 22.05.
        """
    ).strip()

    assert nixos.find_nix_build_error(stderr) == expected


def test_find_nix_build_error_oneline():
    stderr = textwrap.dedent(
        """
        copying path '/nix/store/24lrf2pp03i902sfpx2wfsxvv7xclcxc-bind-9.18.19-man' from 'https://s3.whq.fcio.net/hydra'...
        copying path '/nix/store/hx1mzy0d8kx3a8fzncz42m8ij06pm0s1-bc-1.07.1' from 'https://s3.whq.fcio.net/hydra'...
        error: opening directory '/nix/store/v04xnxah48g4m9lp4151xw70yr2dlcc9-unit-script-acme-selfsigned-test-start': Too many open files
        """
    )
    expected = textwrap.dedent(
        """
        opening directory '/nix/store/v04xnxah48g4m9lp4151xw70yr2dlcc9-unit-script-acme-selfsigned-test-start': Too many open files
        """
    ).strip()

    assert nixos.find_nix_build_error(stderr) == expected


@pytest.fixture
def dirsetup(tmpdir):
    drv = tmpdir.mkdir("abcdef-linux-4.4.27")
    current = tmpdir.mkdir("current")
    bzImage = drv.ensure("bzImage")
    (current / "kernel").mksymlinkto(bzImage)
    mod = drv.mkdir("lib").mkdir("modules")
    return current / "kernel", mod


def test_kernel_versions_equal(dirsetup, tmpdir):
    kernel, mod = dirsetup
    mod.mkdir("4.4.27")
    assert "4.4.27" == nixos.kernel_version(str(kernel))


def test_kernel_version_empty(dirsetup, tmpdir):
    kernel, mod = dirsetup
    with pytest.raises(RuntimeError):
        nixos.kernel_version(str(kernel))


def test_multiple_kernel_versions(dirsetup, tmpdir):
    kernel, mod = dirsetup
    mod.mkdir("4.4.27")
    mod.mkdir("4.4.28")
    with pytest.raises(RuntimeError):
        nixos.kernel_version(str(kernel))
