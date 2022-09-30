import json
import traceback
import unittest.mock
from unittest.mock import Mock, patch

import fc.manage.postgresql
import fc.util.postgresql
import pytest
import typer.testing
from fc.util.postgresql import (
    PGVersion,
    build_new_bin_dir,
    prepare_upgrade,
    run_pg_upgrade,
    run_pg_upgrade_check,
)


@pytest.fixture
def pg10_data_dir(log, tmp_path, monkeypatch):
    data_dir = tmp_path / "postgresql/10"
    data_dir.mkdir(parents=True)
    (data_dir / "package")
    (data_dir / "PG_VERSION").write_text("10")
    (data_dir / "fcio_stopper").touch()
    monkeypatch.setattr(
        "fc.util.postgresql.get_current_pgdata_from_service",
        (lambda: data_dir),
    )
    return data_dir


@pytest.mark.needs_nix
def test_build_new_bin_dir(logger, tmp_path):
    new_bin_dir = build_new_bin_dir(logger, tmp_path, PGVersion.PG11)
    assert (new_bin_dir / "pg_upgrade").exists()


def test_prepare_upgrade(logger, pg10_data_dir, monkeypatch, tmp_path):
    monkeypatch.setattr("shutil.chown", Mock())
    monkeypatch.setattr(
        "fc.util.postgresql.get_existing_dbs",
        (
            lambda *a: {
                "postgres": {
                    "datname": "postgres",
                    "datcollate": "C",
                    "datctype": "C",
                }
            }
        ),
    )
    monkeypatch.setattr("fc.util.postgresql.is_service_running", (lambda: True))
    new_data_dir = tmp_path / "postgresql/11"
    new_data_dir.mkdir()
    (new_data_dir / "fcio_upgrade_prepared").touch()
    new_bin_dir = new_data_dir
    fc.util.postgresql.prepare_upgrade(
        logger,
        old_data_dir=pg10_data_dir,
        new_version=PGVersion.PG11,
        new_bin_dir=new_bin_dir,
        new_data_dir=new_data_dir,
        expected_databases=[],
    )


def test_run_pg_upgrade(logger, tmp_path, pg10_data_dir, monkeypatch):
    monkeypatch.setattr("fc.util.postgresql.run_as_postgres", Mock())
    new_data_dir = tmp_path / "postgresql/11"
    new_data_dir.mkdir()
    new_bin_dir = new_data_dir
    (new_data_dir / "fcio_upgrade_prepared").touch()
    run_pg_upgrade(
        logger,
        old_data_dir=pg10_data_dir,
        new_bin_dir=new_bin_dir,
        new_data_dir=new_data_dir,
    )

    assert (new_data_dir / "fcio_migrated_from").exists()
    assert (new_data_dir / "fcio_migrated_from.log").exists()
    assert not (new_data_dir / "fcio_upgrade_prepared").exists()
    assert (pg10_data_dir / "fcio_migrated_to").exists()
    assert (pg10_data_dir / "fcio_migrated_to.log").exists()
    assert not (pg10_data_dir / "package").exists()
    assert not (pg10_data_dir / "fcio_stopper").exists()
