import json
from unittest.mock import Mock

import fc.manage.postgresql
import fc.util.postgresql
import pytest
from fc.util.postgresql import (
    PGVersion,
    build_new_bin_dir,
    get_existing_dbs,
    run_pg_upgrade,
)


@pytest.fixture
def old_data_dir(log, tmp_path, monkeypatch):
    data_dir = tmp_path / "postgresql/14"
    data_dir.mkdir(parents=True)
    (data_dir / "package")
    (data_dir / "PG_VERSION").write_text("14")
    (data_dir / "fcio_stopper").touch()
    monkeypatch.setattr(
        "fc.util.postgresql.get_current_pgdata_from_service",
        (lambda: data_dir),
    )
    return data_dir


@pytest.mark.needs_nix
def test_build_new_bin_dir(logger, tmp_path):
    new_bin_dir = build_new_bin_dir(logger, tmp_path, PGVersion.PG15)
    assert (new_bin_dir / "pg_upgrade").exists()


def test_prepare_upgrade(logger, old_data_dir, monkeypatch, tmp_path):
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
    monkeypatch.setattr(
        "fc.util.postgresql.is_service_running", (lambda: True)
    )
    new_data_dir = tmp_path / "postgresql/15"
    new_data_dir.mkdir()
    (new_data_dir / "fcio_upgrade_prepared").touch()
    new_bin_dir = new_data_dir
    fc.util.postgresql.prepare_upgrade(
        logger,
        old_data_dir=old_data_dir,
        new_version=PGVersion.PG15,
        new_bin_dir=new_bin_dir,
        new_data_dir=new_data_dir,
        expected_databases=[],
    )


EXPECTED_EXISTING_DBS = {
    "postgres": {
        "datname": "postgres",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "root": {
        "datname": "root",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "template1": {
        "datname": "template1",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "template0": {
        "datname": "template0",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "nagios": {
        "datname": "nagios",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "mydb": {
        "datname": "mydb",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
    "otherdb": {
        "datname": "otherdb",
        "datcollate": "en_US.UTF-8",
        "datctype": "en_US.UTF-8",
    },
}

EXISTING_DBS_STOPPED_POSTGRES = """\
 1: datname     (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "postgres"        (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "root"    (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "template1"       (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "template0"       (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "nagios"  (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "mydb"    (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
 1: datname = "otherdb" (typeid = 19, len = 64, typmod = -1, byval = f)
 2: datcollate = "en_US.UTF-8"  (typeid = 19, len = 64, typmod = -1, byval = f)
 3: datctype = "en_US.UTF-8"    (typeid = 19, len = 64, typmod = -1, byval = f)
----
"""

EXISTING_DBS_RUNNING_POSTGRES = """\
postgres|en_US.UTF-8|en_US.UTF-8
root|en_US.UTF-8|en_US.UTF-8
template1|en_US.UTF-8|en_US.UTF-8
template0|en_US.UTF-8|en_US.UTF-8
nagios|en_US.UTF-8|en_US.UTF-8
mydb|en_US.UTF-8|en_US.UTF-8
otherdb|en_US.UTF-8|en_US.UTF-8
"""


@pytest.fixture
def psql_existing_dbs_stopped(monkeypatch):
    def fake_psql_call(*_a, **_k):
        class FakeProc:
            stdout = EXISTING_DBS_STOPPED_POSTGRES

        return FakeProc

    monkeypatch.setattr("fc.util.postgresql.run_as_postgres", fake_psql_call)


def test_get_existing_dbs_stopped_postgres(
    logger, old_data_dir, psql_existing_dbs_stopped
):
    assert (
        get_existing_dbs(
            logger,
            old_data_dir,
            postgres_running=False,
            expected_dbs=["mydb", "otherdb"],
        )
        == EXPECTED_EXISTING_DBS
    )


@pytest.fixture
def psql_existing_dbs_running(monkeypatch):
    def fake_psql_call(*_a, **_k):
        class FakeProc:
            stdout = EXISTING_DBS_RUNNING_POSTGRES

        return FakeProc

    monkeypatch.setattr("fc.util.postgresql.run_as_postgres", fake_psql_call)


def test_get_existing_dbs_running_postgres(
    logger, old_data_dir, psql_existing_dbs_running
):
    assert (
        get_existing_dbs(
            logger,
            old_data_dir,
            postgres_running=True,
            expected_dbs=["mydb", "otherdb"],
        )
        == EXPECTED_EXISTING_DBS
    )


def test_get_existing_dbs_running_postgres_ignore_expected(
    logger, old_data_dir, psql_existing_dbs_running
):
    assert (
        get_existing_dbs(
            logger, old_data_dir, postgres_running=True, expected_dbs=None
        )
        == EXPECTED_EXISTING_DBS
    )


def test_get_existing_dbs_running_postgres_should_raise_for_unknown(
    logger, old_data_dir, psql_existing_dbs_running
):
    with pytest.raises(fc.util.postgresql.UnexpectedDatabasesFound):
        get_existing_dbs(
            logger,
            old_data_dir,
            postgres_running=True,
            expected_dbs=["mydb"],
        )


def test_run_pg_upgrade(logger, tmp_path, old_data_dir, monkeypatch):
    monkeypatch.setattr("fc.util.postgresql.run_as_postgres", Mock())
    monkeypatch.setattr(
        "fc.util.postgresql.pg_upgrade_clone_available",
        Mock(return_value=True),
    )
    new_data_dir = tmp_path / "postgresql/15"
    new_data_dir.mkdir()
    new_bin_dir = new_data_dir
    (new_data_dir / "fcio_upgrade_prepared").touch()
    run_pg_upgrade(
        logger,
        old_data_dir=old_data_dir,
        new_bin_dir=new_bin_dir,
        new_data_dir=new_data_dir,
    )

    assert (new_data_dir / "fcio_migrated_from").exists()
    assert (new_data_dir / "fcio_migrated_from.log").exists()
    assert not (new_data_dir / "fcio_upgrade_prepared").exists()
    assert (old_data_dir / "fcio_migrated_to").exists()
    assert (old_data_dir / "fcio_migrated_to.log").exists()
    assert not (old_data_dir / "package").exists()
    assert not (old_data_dir / "fcio_stopper").exists()
