import json
import unittest.mock
from pathlib import Path

from fc.util.enc import initialize_enc, update_enc


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
