import json
import traceback
from unittest.mock import Mock, patch

import fc.manage.postgresql
import pytest
import typer.testing


@pytest.fixture
def old_data_dir(tmp_path, monkeypatch):
    old_data_dir = tmp_path / "postgresql/14/package"
    old_data_dir.mkdir(parents=True)

    monkeypatch.setattr(
        "fc.util.postgresql.find_old_data_dir", Mock(return_value=old_data_dir)
    )

    return old_data_dir


@pytest.fixture
def invoke_app(log, tmp_path, old_data_dir):
    runner = typer.testing.CliRunner()
    main_args = (
        "--verbose",
        "--logdir",
        tmp_path / "log",
        "--pg-data-root",
        tmp_path / "postgresql",
    )

    (tmp_path / "postgresql/15").mkdir()
    (tmp_path / "log").mkdir()

    def _invoke_app(*args):
        result = runner.invoke(fc.manage.postgresql.app, main_args + args)
        if result.exc_info:
            traceback.print_tb(result.exc_info[2])
        assert result.exit_code == 0, (
            f"unexpected exit code, output:" f" {result.output}"
        )

        return result

    return _invoke_app


def test_invoke_main_help(invoke_app):
    result = invoke_app("--help")
    assert "Usage: fc-postgresql" in result.output


def test_invoke_list_versions(invoke_app, monkeypatch, tmp_path):
    monkeypatch.setattr(
        "fc.util.postgresql.get_current_pgdata_from_service",
        (lambda: tmp_path / "postgresql/14"),
    )
    monkeypatch.setattr("fc.util.postgresql.is_service_running", (lambda: True))
    result = invoke_app("list-versions")
    print(result.output)


@patch("fc.util.postgresql.run_pg_upgrade")
@patch("fc.util.postgresql.run_pg_upgrade_check")
@patch("fc.util.postgresql.prepare_upgrade")
@patch("fc.util.postgresql.build_new_bin_dir")
def test_invoke_upgrade(
    build_new_bin_dir: Mock,
    prepare_upgrade: Mock,
    run_pg_upgrade_check: Mock,
    run_pg_upgrade: Mock,
    invoke_app,
):
    invoke_app("upgrade", "--new-version", "15")
    build_new_bin_dir.assert_called()
    prepare_upgrade.assert_called()
    run_pg_upgrade_check.assert_called()
    # Make sure we don't run destructive things by default.
    run_pg_upgrade.assert_not_called()


@patch("fc.util.postgresql.get_current_pgdata_from_service")
@patch("fc.util.postgresql.run_pg_upgrade")
@patch("fc.manage.postgresql.stop_pg")
@patch("fc.util.postgresql.prepare_upgrade")
@patch("fc.util.postgresql.build_new_bin_dir")
def test_invoke_upgrade_now(
    build_new_bin_dir: Mock,
    prepare_upgrade: Mock,
    stop_pg,
    run_pg_upgrade: Mock,
    get_current_pg_data_from_service,
    invoke_app,
):
    invoke_app("upgrade", "--new-version", "15", "--upgrade-now")
    build_new_bin_dir.assert_called()
    prepare_upgrade.assert_called()
    run_pg_upgrade.assert_called()


@patch("fc.util.postgresql.run_pg_upgrade")
@patch("fc.util.postgresql.run_pg_upgrade_check")
@patch("fc.util.postgresql.prepare_upgrade")
@patch("fc.util.postgresql.get_current_pgdata_from_service")
@patch("fc.util.postgresql.get_pg_version_from_data_dir")
@patch("fc.util.postgresql.build_new_bin_dir")
def test_invoke_prepare_autoupgrade(
    build_new_bin_dir: Mock,
    get_pg_version_from_data_dir: Mock,
    get_current_pgdata_from_service: Mock,
    prepare_upgrade: Mock,
    run_pg_upgrade_check: Mock,
    run_pg_upgrade: Mock,
    invoke_app,
    tmp_path,
    monkeypatch,
):
    config = tmp_path / "autoupgrade.json"
    conf = {"expected_databases": ["test"]}
    config.write_text(json.dumps(conf), encoding="utf8")
    monkeypatch.setattr("fc.util.postgresql.is_service_running", (lambda: True))
    invoke_app("prepare-autoupgrade", "--config", config, "--new-version", "15")
    build_new_bin_dir.assert_called()
    prepare_upgrade.assert_called()
    run_pg_upgrade_check.assert_called()
    # Make sure we don't run destructive things by default.
    run_pg_upgrade.assert_not_called()
