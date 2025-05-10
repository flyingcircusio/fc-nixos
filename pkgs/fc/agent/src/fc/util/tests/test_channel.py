from unittest import mock

import structlog

from fc.util.channel import Channel
from fc.util.nixos import Specialisation


def prepare_channel(version, tmp_path, monkeypatch, specialisation=None):
    log = structlog.get_logger()
    channel = Channel(log, "file://")
    channel.REBOOT_DELAY = 2
    channel.system_path = tmp_path / "new_system"

    variations = [("", "")]
    if specialisation:
        variations.append((f"specialisation/{specialisation}", specialisation))

    for p, spec in variations:
        path = channel.system_path / p
        path.mkdir(parents=True)
        if spec:
            version_label = f"{spec}-{version}"
        else:
            version_label = version

        (path / "nixos-version").write_text(version_label)
        (path / "bin").mkdir()
        s_t_c = path / "bin/switch-to-configuration"
        s_t_c.write_text("#!/bin/sh\n")
        s_t_c.chmod(0o777)

    check_call = mock.Mock()
    monkeypatch.setattr("subprocess.check_call", check_call)

    return channel


def test_switch_to_config_reboot_on_upgrade_no_specialisation(
    log, tmp_path, monkeypatch
):
    monkeypatch.setattr("fc.util.nixos.running_system_version", lambda: "24.11")

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
    log, tmp_path, monkeypatch
):
    monkeypatch.setattr(
        "fc.util.nixos.running_system_version", lambda: "primary-24.11"
    )

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
    log, tmp_path, monkeypatch
):
    monkeypatch.setattr("fc.util.nixos.running_system_version", lambda: "24.11")

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


def test_switch_to_config_no_reboot_on_same_version(log, tmp_path, monkeypatch):
    monkeypatch.setattr("fc.util.nixos.running_system_version", lambda: "25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch)
    channel.switch_to_configuration("", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_keep(
    log, tmp_path, monkeypatch
):
    monkeypatch.setattr(
        "fc.util.nixos.running_system_version", lambda: "primary-25.05"
    )

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    channel.switch_to_configuration("primary", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")


def test_switch_to_config_no_reboot_on_specialisation_change(
    log, tmp_path, monkeypatch
):
    monkeypatch.setattr("fc.util.nixos.running_system_version", lambda: "25.05")

    channel = prepare_channel("25.05", tmp_path, monkeypatch, "primary")
    channel.switch_to_configuration("primary", tmp_path)

    assert not log.has("release-change-requires-reboot")
    assert not log.has("reboot-scheduled")
    assert log.has("system-switch-succeeded")
