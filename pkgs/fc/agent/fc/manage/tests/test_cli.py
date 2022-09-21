import json
import traceback
import unittest.mock
from unittest.mock import Mock

import fc.maintenance.cli
import fc.manage.cli
import fc.manage.manage
import pytest
import typer.testing

CHANNEL_URL = (
    "https://hydra.flyingcircus.io/build/138288/download/1/nixexprs.tar.xz"
)
ENVIRONMENT = "test"

ENC = {
    "parameters": {
        "environment": ENVIRONMENT,
        "environment_url": CHANNEL_URL,
    }
}


@pytest.fixture
def invoke_app(log, tmpdir, agent_maintenance_config):
    runner = typer.testing.CliRunner()
    enc_file = tmpdir / "enc.json"
    main_args = (
        "--verbose",
        "--logdir",
        tmpdir,
        "--tmpdir",
        tmpdir,
        "--lock-dir",
        tmpdir,
        "--enc-path",
        enc_file,
    )

    tmpdir.mkdir("fc-agent")
    enc_file.write_text(json.dumps(ENC), encoding="utf8")

    def _invoke_app(*args):
        result = runner.invoke(fc.manage.cli.app, main_args + args)
        if result.exc_info:
            traceback.print_tb(result.exc_info[2])
        assert result.exit_code == 0, (
            f"unexpected exit code, output:" f" {result.output}"
        )

    return _invoke_app


# Tests for new-style and old-style calls


@pytest.mark.parametrize("cmd", [["switch"], ["-b"]])
@unittest.mock.patch("fc.manage.manage.switch")
@unittest.mock.patch("fc.manage.manage.initial_switch_if_needed")
@unittest.mock.patch("fc.util.logging.drop_cmd_output_logfile")
def test_invoke_switch(
    drop_cmd_output_logfile: Mock,
    initial_switch_if_needed: Mock,
    switch: Mock,
    log,
    logger,
    invoke_app,
    cmd,
):
    initial_switch_if_needed.return_value = False
    switch.return_value = False
    invoke_app(*cmd)
    expected = {
        "log": switch.call_args.kwargs["log"],
        "enc": ENC,
        "lazy": False,
    }
    assert switch.call_args.kwargs == expected

    initial_switch_if_needed.assert_called_once()
    drop_cmd_output_logfile.assert_called_once()
    assert log.has("fc-manage-start")
    assert log.has("fc-manage-succeeded")


@pytest.mark.parametrize("cmd", [["switch"], ["-b"]])
@unittest.mock.patch("fc.manage.manage.switch")
@unittest.mock.patch("fc.manage.manage.initial_switch_if_needed")
@unittest.mock.patch("fc.util.logging.drop_cmd_output_logfile")
def test_invoke_switch_should_not_drop_meaningful_cmd_output(
    drop_cmd_output_logfile: Mock,
    initial_switch_if_needed: Mock,
    switch: Mock,
    log,
    logger,
    invoke_app,
    cmd,
):
    initial_switch_if_needed.return_value = True
    switch.return_value = False
    invoke_app(*cmd)
    switch.assert_called_once()
    drop_cmd_output_logfile.assert_not_called()


@pytest.mark.parametrize("cmd", [["switch", "--update-channel"], ["-c"]])
@unittest.mock.patch("fc.manage.manage.switch_with_update")
def test_invoke_switch_with_channel_update(
    switch_with_update, log, logger, invoke_app, cmd
):
    invoke_app(*cmd)
    expected = {
        "log": switch_with_update.call_args.kwargs["log"],
        "enc": ENC,
        "lazy": False,
    }
    assert switch_with_update.call_args.kwargs == expected

    assert log.has("fc-manage-start")
    assert log.has("fc-manage-succeeded")


@pytest.mark.parametrize("cmd", [["update-enc"], ["-e"]])
@unittest.mock.patch("fc.util.enc.update_enc")
def test_invoke_update_enc(
    update_enc,
    log,
    logger,
    invoke_app,
    cmd,
):
    invoke_app(*cmd)
    update_enc.assert_called_once()


@pytest.mark.parametrize(
    "cmd",
    [
        ["switch", "--update-enc"],
        ["switch", "-e"],
        ["-be"],
    ],
)
@unittest.mock.patch("fc.manage.manage.switch")
@unittest.mock.patch("fc.util.enc.update_enc")
@unittest.mock.patch("fc.manage.manage.initial_switch_if_needed")
def test_invoke_switch_and_update_enc(
    initial_switch_if_needed: Mock,
    update_enc: Mock,
    switch: Mock,
    log,
    logger,
    invoke_app,
    cmd,
):
    initial_switch_if_needed.return_value = False
    invoke_app(*cmd)
    initial_switch_if_needed.assert_called_once()
    update_enc.assert_called_once()
    switch.assert_called_once()


@pytest.mark.parametrize(
    "cmd",
    [
        ["switch", "--update-channel", "--update-enc"],
        ["switch", "-c", "-e"],
        ["-ce"],
    ],
)
@unittest.mock.patch("fc.manage.manage.switch_with_update")
@unittest.mock.patch("fc.util.enc.update_enc")
def test_invoke_switch_with_channel_update_and_update_enc(
    update_enc,
    switch_with_update,
    log,
    logger,
    invoke_app,
    cmd,
):
    invoke_app(*cmd)
    update_enc.assert_called_once()
    switch_with_update.assert_called_once()


# Tests for commands without old-style equivalent


@unittest.mock.patch("fc.manage.manage.dry_activate")
def test_invoke_dry_activate(manage_func, log, logger, invoke_app):
    channel_url = "https://example.com/custom_nixexprs.tar.xz"
    invoke_app("dry-activate", channel_url)
    expected = {
        "log": manage_func.call_args.kwargs["log"],
        "channel_url": channel_url,
    }
    assert manage_func.call_args.kwargs == expected
