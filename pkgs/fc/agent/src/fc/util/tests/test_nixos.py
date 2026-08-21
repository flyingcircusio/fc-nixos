import shlex
import textwrap
from pathlib import Path
from unittest import mock

import pytest
import structlog

from fc.util import nixos
from fc.util.channel import Channel
from fc.util.tests import PollingFakePopen

structlog.configure(wrapper_class=structlog.BoundLogger)

FC_CHANNEL = (
    "https://hydra.flyingcircus.io/build/93111/download/1/nixexprs.tar.xz"
)


@pytest.fixture
def mock_resolve_url_redirects(monkeypatch):
    m = mock.Mock()
    m.side_effect = lambda url: url
    monkeypatch.setattr("fc.util.nixos.resolve_url_redirects", m)


def test_get_fc_channel_build(log):
    build = nixos.get_fc_channel_build(FC_CHANNEL)
    assert build == "93111"


def test_get_fc_channel_build_should_warn_for_non_fc_channel(log):
    invalid_channel = "http://invalid"
    build = nixos.get_fc_channel_build(invalid_channel)
    assert build is None
    assert log.has("no-fc-channel-url", channel_url=invalid_channel)


def test_build_with_changes(
    log, monkeypatch, tmp_path, mock_resolve_url_redirects
):
    channel = Channel(
        log,
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz",
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
        f"nix-build --no-build-output <nixpkgs/nixos> -A system -I {channel.resolved_url} --out-link /run/fc-agent-test -v"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll="stderr"
    )

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)
    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *args: 2_000_000
    )

    eval_warnings_file = tmp_path / "fcio_nix_eval_warnings"
    built_system_path = nixos.build(
        channel,
        build_options=["-v"],
        out_link="/run/fc-agent-test",
        eval_warnings_file=eval_warnings_file,
    )

    popen_mock.assert_called_once_with(
        cmd,
        stdout=-1,
        stderr=-1,
        preexec_fn=nixos._increase_soft_fd_limit,
        text=True,
    )
    assert built_system_path == system_path
    assert log.has(
        "system-build-succeeded",
        changed=True,
        build_output=build_output.strip(),
    )
    assert eval_warnings_file.exists()


def test_build_unchanged(log, monkeypatch, mock_resolve_url_redirects):
    channel = Channel(
        log,
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz",
    )
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    build_output = "\n"

    cmd = shlex.split(
        f"nix-build --no-build-output <nixpkgs/nixos> -A system -I {channel.resolved_url} --no-out-link"
    )

    nix_build_fake = PollingFakePopen(
        cmd, stdout=system_path, stderr=build_output, poll="stderr"
    )

    popen_mock = mock.Mock(return_value=nix_build_fake)
    monkeypatch.setattr("subprocess.Popen", popen_mock)
    monkeypatch.setattr(
        "fc.util.nixos.system_closure_size", lambda *args: 2_000_000
    )

    built_system_path = nixos.build(
        channel, eval_warnings_file=Path("/dev/null")
    )

    assert built_system_path == system_path
    popen_mock.assert_called_once_with(
        cmd,
        stdout=-1,
        stderr=-1,
        preexec_fn=nixos._increase_soft_fd_limit,
        text=True,
    )
    assert log.has("system-build-succeeded", changed=False)


def test_build_fail(log, monkeypatch, mock_resolve_url_redirects):
    channel = Channel(
        log,
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz",
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
        f"nix-build --no-build-output <nixpkgs/nixos> -A system -I {channel.resolved_url} --no-out-link"
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
        nixos.build(channel, eval_warnings_file=Path("/dev/null"))

    assert log.has("system-build-failed", stderr=build_output.strip())


def test_switch_to_system(log, monkeypatch):
    system_path = Path(
        "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    )
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
    monkeypatch.setattr(
        "pathlib.Path.resolve",
        lambda p: system_path if p == system_path else "other",
    )

    changed = nixos.switch_to_system(
        system_path, lazy=True, switch_type="switch"
    )
    assert changed


def test_switch_to_system_lazy_unchanged(log, monkeypatch):
    system_path = "/nix/store/v49jzgwblcn9vkrmpz92kzw5pkbsn0vz-nixos-system-test-21.05.1367.817a5b0"
    monkeypatch.setattr("pathlib.Path.resolve", lambda p: system_path)

    changed = nixos.switch_to_system(
        system_path, lazy=True, switch_type="switch"
    )
    assert not changed
    assert log.has("system-switch-skip")


def test_update_system_channel(log, monkeypatch):
    current_channel = FC_CHANNEL
    next_channel = (
        "https://hydra.flyingcircus.io/build/93222/download/1/nixexprs.tar.xz"
    )

    current_nixos_channel_url = mock.Mock()
    current_nixos_channel_url.side_effect = current_channel
    monkeypatch.setattr(
        "fc.util.nixos.current_nixos_channel_url", current_nixos_channel_url
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


def test_find_nix_eval_warnings():
    stderr = textwrap.dedent("""\
        trace: Obsolete option `flyingcircus.roles.statshost.enable' is used. It was renamed to `flyingcircus.roles.statshost-global.enable'.
        trace: evaluation warning: 1 NixOS module system warning
        evaluation warning: 'imagemagick7' has been renamed to/replaced by 'imagemagick'
        The option `services.nginx.virtualHosts."test66.fe.rzob.fcio.net".forcSSL' does not exist. Definition values:
        - In `/etc/local/nixos/dev_vm.nix': true
        """)
    warnings = nixos.find_nix_eval_warnings(stderr)
    assert len(warnings) == 2
    assert "1 NixOS module system warning" in warnings
    assert (
        "'imagemagick7' has been renamed to/replaced by 'imagemagick'"
        in warnings
    )

    assert nixos.find_nix_eval_warnings("") == []


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
def dirsetup(tmp_path):
    drv = tmp_path / "abcdef-linux-4.4.27"
    drv.mkdir()
    bzImage = drv / "bzImage"
    bzImage.touch()
    current = tmp_path / "current"
    current.mkdir()
    (current / "kernel").symlink_to(bzImage)
    return current


def test_kernel_versions_equal(dirsetup, tmpdir):
    system = dirsetup
    assert nixos.system_kernel(system) == nixos.system_kernel(system)
    assert not nixos.system_kernel(system) != nixos.system_kernel(system)
    assert nixos.system_kernel(system) == nixos.kernel_package(
        Path("/nix/store") / "abcdef-linux-4.4.27" / "bzImage"
    )
    assert nixos.system_kernel(system) == nixos.KernelIdentifier(
        "abcdef-linux-4.4.27"
    )


def test_kernel_version_empty(dirsetup, tmpdir):
    (dirsetup / "kernel").unlink()
    with pytest.raises(RuntimeError):
        nixos.system_kernel(dirsetup)


def test_KernelIdentifier():
    id_regular = nixos.KernelIdentifier("abcdef-linux-4.4.27")
    id_regular_rebuild = nixos.KernelIdentifier("asdfgh-linux-4.4.27")
    id_patched = nixos.KernelIdentifier("abcdef-linuxPatched-4.4.27")
    id_bogus = nixos.KernelIdentifier("somebogusString")

    assert id_regular != id_regular_rebuild
    assert id_regular != id_patched
    assert str(id_regular) == str(id_regular_rebuild)
    assert str(id_regular) != str(id_patched)
    assert str(id_regular) == "<Kernel: linux v4.4.27>"
    assert str(id_patched) == "<Kernel: linuxPatched v4.4.27>"
    assert str(id_bogus) == "<Kernel: somebogusString>"


def test_os_release_parser(tmp_path):
    os_release = tmp_path / "etc/os-release"
    os_release.parent.mkdir(parents=True)
    os_release.write_text("""\


# comment with emptly lines before
A=1
B="fdasfda"
C='word word = word word'
D=""
E=
""")

    assert nixos.os_release(tmp_path) == {
        "A": "1",
        "B": "fdasfda",
        "C": "word word = word word",
        "D": "",
        "E": "",
    }

    os_release.write_text("""\
B="bad quoting'
""")

    with pytest.raises(AssertionError):
        assert nixos.os_release(tmp_path)


def prepare_channel(version, tmp_path, monkeypatch, specialisation=None):
    log = structlog.get_logger()
    channel = Channel(log, "file://")
    channel.system_path = tmp_path / "new_system"

    variations = [""]
    if specialisation:
        variations.append(f"specialisation/{specialisation}")

    for p in variations:
        path = channel.system_path / p
        path.mkdir(parents=True)
        os_release = path / "etc/os-release"
        os_release.parent.mkdir()
        os_release.write_text(f"VERSION_ID={version}")
        s_t_c = path / "bin/switch-to-configuration"
        s_t_c.parent.mkdir()
        s_t_c.write_text("#!/bin/sh\n")
        s_t_c.chmod(0o777)

    check_call = mock.Mock()
    monkeypatch.setattr("subprocess.check_call", check_call)

    return channel


@pytest.fixture
def tmp_current_os_release(tmp_path, monkeypatch):
    current_os_release = tmp_path / "etc/os-release"
    current_os_release.parent.mkdir(parents=True)
    monkeypatch.setattr("fc.util.nixos.CURRENT_SYSTEM", tmp_path)
    return current_os_release


def test_switch_to_config_reboot_on_upgrade_no_specialisation(
    log, tmp_path, tmp_current_os_release, monkeypatch
):
    tmp_current_os_release.write_text("VERSION_ID=24.11")

    channel = prepare_channel("25.05", tmp_path, monkeypatch)
    nixos.switch_to_configuration(
        system_path=channel.system_path, specialisation="", lock_dir=tmp_path
    )

    assert log.has(
        "release-change-requires-reboot",
        current_release="24.11",
        next_release="25.05",
    )
    assert log.has(
        "reboot-scheduled",
        _replace_msg="WILL REBOOT IN 1 SECONDS. PRESS Ctrl-C TO ABORT.",
    )
    assert log.has("system-switch-succeeded")


def test_switch_to_config_reboot_on_upgrade_specialisation_keep(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=24.11")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    nixos.switch_to_configuration(
        system_path=channel.system_path,
        specialisation="primary",
        lock_dir=tmp_path,
    )

    assert log.has(
        "release-change-requires-reboot",
        current_release="24.11",
        next_release="25.05",
    )
    assert log.has(
        "reboot-scheduled",
        _replace_msg="WILL REBOOT IN 1 SECONDS. PRESS Ctrl-C TO ABORT.",
    )
    assert log.has("system-switch-succeeded")


def test_switch_to_config_reboot_on_upgrade_specialisation_change(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=24.11")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    nixos.switch_to_configuration(
        system_path=channel.system_path,
        specialisation="primary",
        lock_dir=tmp_path,
    )

    assert log.has(
        "release-change-requires-reboot",
        current_release="24.11",
        next_release="25.05",
    )
    assert log.has(
        "reboot-scheduled",
        _replace_msg="WILL REBOOT IN 1 SECONDS. PRESS Ctrl-C TO ABORT.",
    )
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_same_version(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch)
    nixos.switch_to_configuration(
        system_path=channel.system_path, specialisation="", lock_dir=tmp_path
    )

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_keep(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    nixos.switch_to_configuration(
        system_path=channel.system_path,
        specialisation="primary",
        lock_dir=tmp_path,
    )

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_change(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    nixos.switch_to_configuration(
        system_path=channel.system_path,
        specialisation="primary",
        lock_dir=tmp_path,
    )

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")
