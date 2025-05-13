from unittest import mock
import pytest
import structlog

from fc.util.channel import Channel


def prepare_channel(version, tmp_path, monkeypatch, specialisation=None):
    log = structlog.get_logger()
    channel = Channel(log, "file://")
    channel.REBOOT_DELAY = 2
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
    channel.switch_to_configuration("", tmp_path)

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
    channel.switch_to_configuration("primary", tmp_path)

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
    channel.switch_to_configuration("primary", tmp_path)

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


def test_switch_to_config_no_reboot_on_same_version(log, tmp_path, monkeypatch, tmp_current_os_release):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch)
    channel.switch_to_configuration("", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_keep(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    channel.switch_to_configuration("primary", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_change(
    log, tmp_path, monkeypatch, tmp_current_os_release
):
    tmp_current_os_release.write_text("VERSION_ID=25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    channel.switch_to_configuration("primary", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")
