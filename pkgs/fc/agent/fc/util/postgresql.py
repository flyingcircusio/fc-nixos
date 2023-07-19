import getpass
import os
import re
import shutil
import tempfile
from datetime import datetime
from enum import Enum
from pathlib import Path
from subprocess import CalledProcessError, run

MIGRATED_TO_TEMPLATE = """\
WARNING: This data directory should not be used anymore!

Migrated to {new_data_dir} at {dt} by `fc-postgresql` with command:

{upgrade_cmd}
"""


MIGRATED_FROM_TEMPLATE = """\
Migrated from {old_data_dir} at {dt} by `fc-postgresql` with command:

{upgrade_cmd}
"""


PREPARED_TEMPLATE = """\
Prepared as new data directory for a migration from {old_data_dir} by
`fc-postgresql` with command:

{initdb_cmd}
"""


class PGVersion(str, Enum):
    PG11 = "11"
    PG12 = "12"
    PG13 = "13"
    PG14 = "14"
    PG15 = "15"


def run_as_postgres(cmd, **kwargs):
    if getpass.getuser() != "postgres":
        cmd = ["sudo", "-u", "postgres"] + cmd

    return run(cmd, text=True, **kwargs)


def get_current_pgdata_from_service():
    current_pgdata_cmd = [
        "systemctl",
        "show",
        "postgresql",
        "--property",
        "Environment",
        "--value",
    ]

    proc = run(
        current_pgdata_cmd,
        check=True,
        capture_output=True,
        text=True,
    )

    current_pgdata = [
        Path(p.removeprefix("PGDATA="))
        for p in proc.stdout.split()
        if p.startswith("PGDATA")
    ]

    if current_pgdata:
        return current_pgdata[0]


def is_service_running():
    proc = run(["systemctl", "is-active", "--quiet", "postgresql.service"])
    return proc.returncode == 0


def build_new_bin_dir(log, pg_data_root: Path, new_version: PGVersion):
    nix_build_new_pg_cmd = [
        "nix-build",
        "<fc>",
        "-A",
        "postgresql_" + new_version.value,
        "--out-link",
        pg_data_root / "pg_upgrade-package",
    ]
    try:
        proc = run(
            nix_build_new_pg_cmd, check=True, text=True, capture_output=True
        )
    except CalledProcessError as e:
        log.error(
            "upgrade-build-postgresql-failed",
            stdout=e.stdout,
            stderr=e.stderr,
        )
        raise
    new_bin_dir = Path(proc.stdout.strip()) / "bin"
    return new_bin_dir


class MultipleOldDirsFound(Exception):
    def __init__(self, found_dirs):
        self.found_dirs = found_dirs


def find_old_data_dir(log, pg_data_root: Path, new_version: PGVersion):
    old_data_dirs = list(sorted(pg_data_root.glob("1[0-5]")))
    log.debug(
        "upgrade-old-data-dir-candidates",
        old_data_dirs=[str(d) for d in old_data_dirs],
    )
    eligible_old_data_dirs = [
        p
        for p in old_data_dirs
        if (p / "package").is_symlink() and p.name < new_version
    ]
    log.debug(
        "upgrade-eligible-old-data-dirs",
        eligible_old_data_dirs=[str(d) for d in eligible_old_data_dirs],
    )
    if not eligible_old_data_dirs:
        return None

    if len(eligible_old_data_dirs) > 1:
        raise MultipleOldDirsFound(eligible_old_data_dirs)

    return eligible_old_data_dirs[0]


def get_pg_version_from_data_dir(log, data_dir: Path):
    try:
        version_str = (data_dir / "PG_VERSION").read_text().strip()
    except OSError:
        log.error(
            "cannot-read-pg-version",
            _replace_msg="Unable to read PG_VERSION from {data_dir}",
            data_dir=data_dir,
        ),
        raise
    try:
        version = PGVersion(version_str)
    except ValueError:
        log.error(
            "unsupported-old-pg-version",
            _replace_msg="Postgres version {version} is not supported",
            version=version_str,
        )
        raise
    log.debug("get-pg-version-from-data-dir", version=version.value)

    return version


def create_new_data_dir(
    log,
    collate,
    ctype,
    new_bin_dir,
    new_data_dir,
    old_data_dir,
):
    log.info(
        "upgrade-init-new-data-dir",
        _replace_msg=("Initializing new data dir in {new_data_dir}."),
        new_data_dir=new_data_dir,
        collate=collate,
        ctype=ctype,
    )
    new_data_dir.mkdir(mode=0o0700)
    shutil.chown(new_data_dir, "postgres", "postgres")
    initdb_cmd = [
        new_bin_dir / "initdb",
        "-D",
        new_data_dir,
        "--lc-collate",
        collate,
        "--lc-ctype",
        ctype,
    ]
    initdb_cmd_str = " ".join(str(e) for e in initdb_cmd)
    log.debug("upgrade-initdb-cmd", cmd=initdb_cmd_str)
    try:
        run_as_postgres(initdb_cmd, check=True)
    except CalledProcessError as e:
        log.error(
            "upgrade-initdb-failed",
            stdout=e.stdout,
            stderr=e.stderr,
        )
        raise
    (new_data_dir / "fcio_upgrade_prepared").write_text(
        PREPARED_TEMPLATE.format(
            initdb_cmd=initdb_cmd_str, old_data_dir=old_data_dir
        )
    )
    shutil.chown(new_data_dir / "fcio_upgrade_prepared", "postgres", "postgres")


class UnexpectedDatabasesFound(Exception):
    def __init__(self, unexpected_dbs):
        self.unexpected_dbs = unexpected_dbs


def get_existing_dbs(log, data_dir, postgres_running, expected_dbs=None):
    if postgres_running:
        get_dbs_cmd = [
            "psql",
            "-qAt",
        ]
    else:
        get_dbs_cmd = [
            data_dir / "package/bin/postgres",
            "--single",
            "-r",
            "/dev/null",
            "-D",
            data_dir,
            "postgres",
        ]
    get_db_sql = "select datname,datcollate,datctype from pg_database"
    try:
        proc = run_as_postgres(
            get_dbs_cmd,
            check=True,
            capture_output=True,
            input=get_db_sql,
        )
    except CalledProcessError as e:
        log.error(
            "upgrade-get-existing-dbs-failed",
            stdout=e.stdout,
            stderr=e.stderr,
        )
        raise
    log.trace("upgrade-existing-dbs-out", stdout=proc.stdout)
    if postgres_running:
        existing_dbs = {}

        for line in proc.stdout.strip().splitlines():
            datname, datcollate, datctype = line.split("|")
            existing_dbs[datname] = {
                "datname": datname,
                "datcollate": datcollate,
                "datctype": datctype,
            }

    else:
        existing_dbs = {}
        current_db = None
        for line in proc.stdout.splitlines():
            line = line.strip()
            if match := re.search(': (.+) = "(.+)"', line):
                column, value = match.groups()
                current_db[column] = value
            elif line.startswith("----"):
                if current_db:
                    existing_dbs[current_db["datname"]] = current_db
                current_db = {}

    if expected_dbs is None:
        log.debug("get-existing-dbs", existing_dbs=existing_dbs)
    else:
        expected_existing_dbs = {
            "fcio_monitoring",
            "nagios",
            "postgres",
            "root",
            "template0",
            "template1",
            *expected_dbs,
        }
        unexpected_dbs = set(existing_dbs) - expected_existing_dbs
        log.debug(
            "get-existing-dbs-unexpected-db-check",
            expected_dbs=expected_dbs,
            existing_dbs=existing_dbs,
            unexpected_dbs=unexpected_dbs,
        )
        if unexpected_dbs:
            raise UnexpectedDatabasesFound(unexpected_dbs)

    return existing_dbs


class NewDataDirUnusable(Exception):
    def __init__(self, data_dir):
        self.data_dir = data_dir


def check_new_data_dir(log, new_data_dir):
    if (new_data_dir / "fcio_upgrade_prepared").exists():
        new_data_dir_mode = new_data_dir.stat().st_mode

        log.debug(
            "upgrade-use-existing-new-data-dir",
            new_data_dir=str(new_data_dir),
            owner=new_data_dir.owner(),
            group=new_data_dir.group(),
            mode=oct(new_data_dir_mode)[3:],
        )
        if new_data_dir_mode != 0o040700:
            log.error("upgrade-existing-data-dir-wrong-mode")
    else:
        raise NewDataDirUnusable(new_data_dir)


def prepare_upgrade(
    log,
    old_data_dir: Path,
    new_version: PGVersion,
    new_bin_dir: Path,
    new_data_dir: Path,
    expected_databases: list[str],
):
    fcio_migrated_to_link = old_data_dir / "fcio_migrated_to"
    if fcio_migrated_to_link.is_symlink():
        log.error(
            "upgrade-old-data-dir-has-migrated-to",
            _replace_msg=(
                "{migrated_to_link} already exists, "
                "looks like the old data dir has been migrated before. "
                "Remove the file if you know what you are doing and try again."
            ),
            migrated_to_link=str(fcio_migrated_to_link),
        )
        raise RuntimeError("upgrade-old-data-dir-has-migrated-to")

    old_version = get_pg_version_from_data_dir(log, old_data_dir)
    postgres_running = is_service_running()
    log.debug(
        "upgrade-from-status",
        old_data_dir=str(old_data_dir),
        postgres_running=postgres_running,
    )
    existing_db_info = get_existing_dbs(
        log,
        old_data_dir,
        postgres_running,
        expected_databases,
    )
    postgres_db = existing_db_info["postgres"]
    collate = postgres_db["datcollate"]
    ctype = postgres_db["datctype"]
    log.info(
        "prepare-upgrade-postgres-db",
        _replace_msg=(
            f"Prepare upgrade from {old_version} -> {new_version}, "
            "using collation {collate} and ctype {ctype}."
        ),
        old_version=old_version.value,
        new_version=new_version.value,
        collate=collate,
        ctype=ctype,
    )
    if new_data_dir.exists():
        check_new_data_dir(
            log,
            new_data_dir,
        )
    else:
        create_new_data_dir(
            log,
            collate,
            ctype,
            new_bin_dir,
            new_data_dir,
            old_data_dir,
        )


def pg_upgrade_clone_available(
    log, new_bin_dir: Path, old_data_dir: Path, new_data_dir: Path
):
    """
    Check if pg_upgrade supports --clone (copy-on-write, reflink) which speeds
    up migration considerably.
    """
    pg_upgrade_help_out = run_as_postgres(
        [new_bin_dir / "pg_upgrade", "--help"],
        capture_output=True,
    ).stdout

    pg_upgrade_has_clone = "--clone" in pg_upgrade_help_out

    src = old_data_dir / "fcio-clone-test"
    src.touch()
    dest = new_data_dir / "fcio-clone-test"
    clone_test = run(
        ["cp", "--reflink=always", src, dest], capture_output=True, text=True
    )

    log.debug(
        "upgrade-clone-check",
        pg_upgrade_has_clone=pg_upgrade_has_clone,
        copy_returncode=clone_test.returncode,
        copy_stderr=clone_test.stderr,
    )

    clone_available = pg_upgrade_has_clone and not clone_test.returncode

    src.unlink(missing_ok=True)
    dest.unlink(missing_ok=True)

    if clone_available:
        log.info(
            "upgrade-clone-supported",
            _replace_msg=(
                "Copying the old database should be very "
                "fast as the pg_upgrade command can use the --clone option."
            ),
        )
    else:
        log.warn(
            "upgrade-clone-not-supported",
            _replace_msg=(
                "Copying the old database may take some time as the pg_upgrade "
                "command does not support the --clone option."
            ),
        )

    return clone_available


def run_pg_upgrade_check(
    log,
    new_bin_dir,
    new_data_dir,
    old_data_dir,
):
    # Tell the user if fast --clone is available.
    pg_upgrade_clone_available(
        log,
        new_bin_dir=new_bin_dir,
        old_data_dir=old_data_dir,
        new_data_dir=new_data_dir,
    )

    upgrade_cmd = [
        new_bin_dir / "pg_upgrade",
        "--old-datadir",
        old_data_dir,
        "--new-datadir",
        new_data_dir,
        "--old-bindir",
        old_data_dir / "package/bin",
        "--new-bindir",
        new_bin_dir,
        "--check",
    ]

    log.debug("upgrade-pg_upgrade-cmd", cmd=upgrade_cmd)
    # pg_upgrade wants to write log files to the current work dir.
    os.chdir(new_data_dir)
    try:
        run_as_postgres(
            upgrade_cmd,
            check=True,
        )
    except CalledProcessError as e:
        log.error(
            "pg-upgrade-check-failed",
            stdout=e.stdout,
            stderr=e.stderr,
        )
        raise


def run_pg_upgrade(
    log,
    new_bin_dir: Path,
    new_data_dir: Path,
    old_data_dir: Path,
):
    upgrade_cmd = [
        new_bin_dir / "pg_upgrade",
        "--old-datadir",
        old_data_dir,
        "--new-datadir",
        new_data_dir,
        "--old-bindir",
        old_data_dir / "package/bin",
        "--new-bindir",
        new_bin_dir,
    ]

    if pg_upgrade_clone_available(
        log,
        new_bin_dir=new_bin_dir,
        old_data_dir=old_data_dir,
        new_data_dir=new_data_dir,
    ):
        upgrade_cmd.append("--clone")

    log.debug("upgrade-pg_upgrade-cmd", cmd=upgrade_cmd)
    # pg_upgrade wants to write log files to the current work dir.
    os.chdir(new_data_dir)
    try:
        run_as_postgres(
            upgrade_cmd,
            check=True,
        )
    except CalledProcessError as e:
        log.error(
            "upgrade-pg-upgrade-failed",
            stdout=e.stdout,
            stderr=e.stderr,
        )
        raise
    migration_finished_dt = datetime.now()
    upgrade_cmd_str = " ".join(str(e) for e in upgrade_cmd)
    (new_data_dir / "fcio_migrated_from").symlink_to(old_data_dir)
    (old_data_dir / "fcio_migrated_to").symlink_to(new_data_dir)
    (new_data_dir / "fcio_migrated_from.log").write_text(
        MIGRATED_FROM_TEMPLATE.format(
            old_data_dir=old_data_dir,
            dt=migration_finished_dt.isoformat(),
            upgrade_cmd=upgrade_cmd_str,
        )
    )
    (old_data_dir / "fcio_migrated_to.log").write_text(
        MIGRATED_TO_TEMPLATE.format(
            new_data_dir=new_data_dir,
            dt=migration_finished_dt.isoformat(),
            upgrade_cmd=upgrade_cmd_str,
        )
    )
    (new_data_dir / "fcio_upgrade_prepared").unlink(missing_ok=True)
    (old_data_dir / "package").unlink(missing_ok=True)
    (old_data_dir / "fcio_stopper").unlink(missing_ok=True)
    old_version = (old_data_dir / "PG_VERSION").read_text().strip()
    nix_gc_root = (
        Path("/nix/var/nix/gcroots/per-user/postgres")
        / f"package_{old_version}"
    )
    nix_gc_root.unlink(missing_ok=True)
