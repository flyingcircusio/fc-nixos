import json
import textwrap
import unittest.mock
from pathlib import Path

import pytest
from fc.util.enc import initialize_enc, initialize_state_version, update_enc


def test_initialize_enc_should_do_nothing_when_enc_present(
    log, logger, tmp_path
):
    enc_path = tmp_path / "enc.json"
    enc_path.write_text("")

    initialize_enc(logger, tmp_path, enc_path)

    assert log.has("initialize-enc-present", enc_path=str(enc_path))


def test_initialize_enc_should_populate_enc_initially(log, logger, tmp_path):
    fc_data_path = tmp_path / "fc-data"
    fc_data_path.mkdir()
    initial_enc_path = fc_data_path / "enc.json"
    initial_enc_path.write_text("")
    enc_path = tmp_path / "enc.json"

    initialize_enc(logger, tmp_path, enc_path)

    assert log.has(
        "initialize-enc-init",
        enc_path=str(enc_path),
        initial_enc_path=str(initial_enc_path),
    )
    assert enc_path.exists()


def test_initialize_enc_should_not_crash_when_initial_data_missing(
    log, logger, tmp_path
):
    enc_path = tmp_path / "enc.json"

    initialize_enc(logger, tmp_path, enc_path)

    assert log.has("initialize-enc-initial-data-not-found")


@pytest.fixture
def os_release_file(tmp_path):
    os_release_file = tmp_path / "os-release"

    os_release_file.write_text(
        textwrap.dedent(
            '''\
        ANSI_COLOR="1;34"
        BUG_REPORT_URL="https://github.com/NixOS/nixpkgs/issues"
        BUILD_ID="24.11.4935.0dbec215"
        CPE_NAME="cpe:/o:nixos:nixos:24.11"
        DEFAULT_HOSTNAME=nixos
        DOCUMENTATION_URL="https://nixos.org/learn.html"
        HOME_URL="https://nixos.org/"
        ID=nixos
        ID_LIKE=""
        IMAGE_ID=""
        IMAGE_VERSION=""
        LOGO="nix-snowflake"
        NAME=NixOS
        PRETTY_NAME="NixOS 24.11 (Vicuna)"
        SUPPORT_END="2025-06-30"
        SUPPORT_URL="https://nixos.org/community.html"
        VARIANT=""
        VARIANT_ID=""
        VENDOR_NAME=NixOS
        VENDOR_URL="https://nixos.org/"
        VERSION="24.11 (Vicuna)"
        VERSION_CODENAME=vicuna
        VERSION_ID="24.11"'''
        )
    )
    return os_release_file


def test_initialize_state_version_from_scratch(
    log, logger, tmp_path, os_release_file, monkeypatch
):
    state_version_file = tmp_path / "state_version"
    monkeypatch.setattr("shutil.chown", unittest.mock.Mock())

    initialize_state_version(logger, os_release_file, state_version_file)
    assert log.has("initialize-state-version"), "Initialization not called"
    assert state_version_file.read_text().strip() == "24.11"


def test_initialize_state_version_fixes_wrong_state_format(
    log, logger, tmp_path, os_release_file, monkeypatch
):
    state_version_file = tmp_path / "state_version"
    state_version_file.write_text("21.05.2213.82e27dc6")
    monkeypatch.setattr("shutil.chown", unittest.mock.Mock())

    initialize_state_version(logger, os_release_file, state_version_file)
    assert log.has(
        "initialize-state-version-format-fixup"
    ), "Fixup logic not called"
    assert state_version_file.read_text().strip() == "21.05"


def test_initialize_state_version_fixup_does_not_crash_on_wrong_format(
    log, logger, tmp_path, os_release_file
):
    state_version_file = tmp_path / "state_version"
    state_version_file.write_text("24Elf")

    initialize_state_version(logger, os_release_file, state_version_file)
    assert log.has(
        "initialize-state-version-format-err"
    ), "Format error not discovered"


@unittest.mock.patch("fc.util.enc.write_system_state")
@unittest.mock.patch("fc.util.enc.update_enc_nixos_config")
@unittest.mock.patch("fc.util.enc.update_inventory")
@unittest.mock.patch("fc.util.enc.initialize_state_version")
def test_update_enc(
    initialize_state_version,
    update_inventory,
    update_enc_nixos_config,
    write_system_state,
    log,
    logger,
    tmp_path,
):
    enc_data = {"parameters": {"test": 1}}
    enc_path = tmp_path / "enc.json"
    with open(enc_path, "w") as wf:
        json.dump(enc_data, wf)

    update_enc(logger, tmp_path, enc_path)

    initialize_state_version.assert_called_once()
    update_inventory.assert_called_with(logger, enc_data)
    update_enc_nixos_config.assert_called_with(logger, enc_data, enc_path)
    write_system_state.assert_called_with(logger)
