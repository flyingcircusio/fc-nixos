import json
import unittest.mock
from unittest.mock import MagicMock

import fc.maintenance.cli
import pytest
import typer.testing

CHANNEL_URL = (
    "https://hydra.flyingcircus.io/build/138288/download/1/nixexprs" ".tar.xz"
)
ENVIRONMENT = "test"

ENC = {
    "parameters": {
        "machine": "virtual",
        "environment": ENVIRONMENT,
        "environment_url": CHANNEL_URL,
    }
}


@pytest.fixture
def invoke_app(tmpdir, agent_maintenance_config):
    runner = typer.testing.CliRunner()
    enc_file = tmpdir / "enc.json"
    main_args = (
        "--verbose",
        "--show-caller-info",
        "--spooldir",
        tmpdir,
        "--logdir",
        tmpdir,
        "--lock-dir",
        tmpdir,
        "--config-file",
        agent_maintenance_config,
        "--enc-path",
        enc_file,
    )

    tmpdir.mkdir("fc-agent")
    enc_file.write_text(json.dumps(ENC), encoding="utf8")

    def _invoke_app(*args):
        with unittest.mock.patch("fc.maintenance.cli.ReqManager"):
            result = runner.invoke(fc.maintenance.cli.app, main_args + args)
            assert (
                result.exit_code == 0
            ), f"unexpected exit code, output: {result.output}"

    return _invoke_app


def test_invoke_run(invoke_app):
    invoke_app("run")
    fc.maintenance.cli.rm.execute.assert_called_once_with(False)
    fc.maintenance.cli.rm.postpone.assert_called_once()
    fc.maintenance.cli.rm.archive.assert_called_once()


def test_invoke_run_all_now(invoke_app):
    invoke_app("run", "--run-all-now")
    fc.maintenance.cli.rm.execute.assert_called_once_with(True)


def test_invoke_list(invoke_app):
    invoke_app("list")
    fc.maintenance.cli.rm.list.assert_called_once()


def test_invoke_show(invoke_app):
    invoke_app("show")
    fc.maintenance.cli.rm.show.assert_called_once()


def test_invoke_show_request_id_dump_yaml(invoke_app):
    invoke_app("show", "123abc", "--dump-yaml")
    fc.maintenance.cli.rm.show.assert_called_once_with("123abc", True)


def test_invoke_delete(invoke_app):
    invoke_app("delete", "123abc")
    fc.maintenance.cli.rm.delete.assert_called_once_with("123abc")


def test_invoke_schedule(invoke_app):
    invoke_app("schedule")
    fc.maintenance.cli.rm.schedule.assert_called_once()


def test_invoke_request_run_script(invoke_app):
    invoke_app("request", "script", "comment", "true")
    fc.maintenance.cli.rm.add.assert_called_once()


@unittest.mock.patch("fc.maintenance.cli.RebootActivity")
def test_invoke_request_warm_reboot(activity, invoke_app):
    invoke_app("request", "reboot")
    activity.assert_called_once_with("reboot")
    fc.maintenance.cli.rm.add.assert_called_once()


@unittest.mock.patch("fc.maintenance.cli.RebootActivity")
def test_invoke_request_cold_reboot(activity, invoke_app):
    invoke_app("request", "reboot", "--cold-reboot")
    activity.assert_called_once_with("poweroff")
    fc.maintenance.cli.rm.add.assert_called_once()


@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_kernel")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_qemu")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_cpu")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_memory")
def test_invoke_request_system_properties_virtual(
    memory, cpu, qemu, kernel, invoke_app
):
    invoke_app("request", "system-properties")
    memory.assert_called_once()
    cpu.assert_called_once()
    qemu.assert_called_once()
    kernel.assert_called_once()


@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_kernel")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_qemu")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_cpu")
@unittest.mock.patch("fc.maintenance.cli.request_reboot_for_memory")
def test_invoke_request_system_properties_virtual(
    memory, cpu, qemu, kernel, tmpdir, invoke_app
):
    enc_file = tmpdir / "enc.json"
    enc = ENC.copy()
    enc["parameters"]["machine"] = "physical"
    enc_file.write_text(json.dumps(enc), encoding="utf8")

    invoke_app("request", "system-properties")
    memory.assert_not_called()
    cpu.assert_not_called()
    qemu.assert_not_called()
    kernel.assert_called_once()


@unittest.mock.patch("fc.maintenance.cli.request_update")
@unittest.mock.patch("fc.maintenance.cli.load_enc")
def test_invoke_request_update(load_enc, request_update, invoke_app):
    invoke_app("request", "update")
    load_enc.assert_called_once()
    request_update.assert_called_once()
    fc.maintenance.cli.rm.add.assert_called_once()
