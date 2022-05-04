import json
import traceback
import unittest.mock

import fc.maintenance.cli
import fc.manage.cli
import fc.manage.manage
import pytest
import typer.testing

CHANNEL_URL = (
    "https://hydra.flyingcircus.io/build/138288/download/1/nixexprs" ".tar.xz"
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
def test_invoke_switch(switch, log, logger, invoke_app, cmd):
    invoke_app(*cmd)
    expected = {
        "log": switch.call_args.kwargs["log"],
        "enc": ENC,
        "lazy": False,
    }
    assert switch.call_args.kwargs == expected

    assert log.has("fc-manage-start")
    assert log.has("fc-manage-succeeded")


@pytest.mark.parametrize("cmd", [["switch", "--update-channel"], ["-c"]])
@unittest.mock.patch("fc.manage.manage.switch_with_update")
def test_invoke_switch_with_channel_update(
    switch, log, logger, invoke_app, cmd
):
    invoke_app(*cmd)
    expected = {
        "log": switch.call_args.kwargs["log"],
        "enc": ENC,
        "lazy": False,
    }
    assert switch.call_args.kwargs == expected

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
def test_invoke_switch_and_update_enc(
    update_enc,
    switch,
    log,
    logger,
    invoke_app,
    cmd,
):
    invoke_app(*cmd)
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
    switch,
    log,
    logger,
    invoke_app,
    cmd,
):
    invoke_app(*cmd)
    update_enc.assert_called_once()
    switch.assert_called_once()


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
