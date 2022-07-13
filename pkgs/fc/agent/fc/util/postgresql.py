import getpass
import os
import re
import shutil
from datetime import datetime
from enum import Enum
from pathlib import Path
from subprocess import CalledProcessError, CompletedProcess, run
from typing import List, Optional

import rich
import structlog
from fc.util.logging import init_logging
from rich.table import Table
from typer import Exit, Option, Typer, confirm, echo

app = Typer()


@app.callback(no_args_is_help=True)
def pg():
    pass


def run_as_postgres(cmd, **kwargs):
    if getpass.getuser() != "postgres":
        cmd = ["sudo", "-u", "postgres"] + cmd

    return run(cmd, text=True, **kwargs)


MIGRATED_TO_TEMPLATE = """\
WARNING: This data directory should not be used anymore!

Migrated to {new_data_dir} at {dt} by `fctl postgresql upgrade` with command:

{upgrade_cmd}
"""


MIGRATED_FROM_TEMPLATE = """\
Migrated from {old_data_dir} at {dt} by `fctl postgresql upgrade` with command:

{upgrade_cmd}
"""

STOPPER_TEMPLATE = """\
`fctl postgresql upgrade` is running with PID {pid}, postgresql service won't
start with this file present. Remove this if you really want to start postgresql.
"""

PREPARED_TEMPLATE = """\
Prepared as new data directory for a migration from {old_data_dir} by
`fctl postgresql upgrade` with command:

{initdb_cmd}
"""


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


def get_db_info_offline(new_data_dir, new_bin_dir):
    pass


def is_service_running():
    proc = run(["systemctl", "is-active", "--quiet", "postgresql.service"])
    return proc.returncode == 0


class PGVersion(str, Enum):
    PG10 = "10"
    PG11 = "11"
    PG12 = "12"
    PG13 = "13"
    PG14 = "14"
    UNKNOWN = None


@app.command(no_args_is_help=True)
def upgrade(
    new_version: PGVersion = Option(
        show_choices=True,
        default=PGVersion.UNKNOWN,
        help=(
            "PostgreSQL version to upgrade to. Should usually be specified. "
            "Upgrading by passing the new data dir and new binary dir "
            "instead is also supported but not recommended."
        ),
    ),
    upgrade_now: bool = Option(
        default=False,
        help="Actually do the upgrade now. If not given, "
        "just create the new data dir and do pre-checks",
    ),
    existing_db_check: bool = Option(
        default=True,
        help="Stop upgrade if unexpected databases are present.",
    ),
    expected: Optional[List[str]] = Option(
        default=[],
        help=(
            "Database name that is expected to be present before the "
            "migration. "
            "Databases created by FCIO automation are automatically added to "
            "the expected databases."
            "Option can be specified multiple times."
        ),
    ),
    new_data_dir: Optional[Path] = Option(
        file_okay=False,
        help=(
            "New PostgreSQL data directory. Will be determined automatically "
            "if --new-version is specified"
        ),
        default=None,
    ),
    new_bin_dir: Optional[Path] = Option(
        file_okay=False,
        exists=True,
        help=(
            "Directory where the new PostgreSQL binaries are. Will be "
            "determined automatically if --new-version is specified"
        ),
        default=None,
    ),
    existing_new_data_dir_check: bool = Option(
        help=(
            "Check if the new data dir looks usable for an upgrade. Disable "
            "this if you still want to use it."
        ),
        default=True,
    ),
    stop: Optional[bool] = Option(default=None),
    nothing_to_do_is_ok: bool = Option(default=True),
    verbose: bool = Option(
        False, "--verbose", "-v", help="Show debug messages and code locations."
    ),
):
    init_logging(verbose, syslog_identifier="fc-postgresql")
    log = structlog.get_logger()

    log.debug("upgrade-start")

    if not (new_data_dir and new_bin_dir):
        if new_version is None:
            echo(
                "If PG version is not specified, both new-data-dir and "
                "new-bin-dir must be specified instead!"
            )
            raise Exit(2)

        nix_build_new_pg_cmd = [
            "nix-build",
            "<nixpkgs>",
            "-A",
            "postgresql_" + new_version.value,
            "--out-link",
            "/srv/postgresql/pg_upgrade-package",
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
            raise Exit(2)

        new_bin_dir = Path(proc.stdout.strip()) / "bin"
        new_data_dir = Path("/srv/postgresql") / new_version.value

    old_data_dirs = list(sorted(Path("/srv/postgresql/").glob("1[0-5]")))

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

        if nothing_to_do_is_ok:
            log.info(
                "upgrade-nothing-to-do",
                _replace_msg=(
                    "No old data directory found that could be migrated."
                ),
            )
            raise Exit()

        log.error(
            "upgrade-no-old-dirs-found",
            _replace_msg=(
                "Couldn't find an eligible data dir for upgrading in "
                "/srv/postgresql. Data dirs must have a symlink called "
                "'package' pointing to the corresponding postgresql package."
            ),
        )

        raise Exit(1)

    if len(eligible_old_data_dirs) > 1:
        log.error(
            "upgrade-multiple-old-dirs-found",
            eligible_old_data_dirs=[str(d) for d in eligible_old_data_dirs],
            _replace_msg=(
                "Found multiple old data dirs, cannot determine "
                "which one to use: {eligible_old_data_dirs}"
            ),
        )
        raise Exit(2)

    old_data_dir = eligible_old_data_dirs[0]
    old_bin_dir = old_data_dir / "package/bin/"

    try:
        old_version_str = (old_data_dir / "PG_VERSION").read_text().strip()
    except OSError:
        log.error(
            "upgrade-cannot-read-old-pg-version",
            _replace_msg=(
                "Unable to read PG_VERSION from {old_data_dir}, "
                "cannot upgrade from this directory."
            ),
            old_data_dir=old_data_dir,
        )
        raise Exit(2)

    try:
        old_version = PGVersion(old_version_str)
    except ValueError:
        log.error(
            "upgrade-unsupported-old-pg-version",
            _replace_msg="Upgrading from version {version} is not supported",
            old_version=old_version_str,
        )
        raise Exit(2)

    log.debug("upgrade-found-old-version", old_version=old_version.value)

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
        raise Exit(2)

    postgres_running = is_service_running()

    log.debug(
        "upgrade-from-status",
        old_data_dir=str(old_data_dir),
        old_bin_dir=str(old_bin_dir),
        postgres_running=postgres_running,
    )

    if upgrade_now:
        if postgres_running and stop is None:
            stop = confirm("Postgresql is running, should I stop it?")

        if postgres_running and not stop:
            log.error(
                "upgrade-postgresql-running",
                _replace_msg=(
                    "PostgreSQL is running! Please make sure that it doesn't "
                    "run during the migration."
                ),
            )
            raise Exit(2)
        elif postgres_running:
            run(
                ["sudo", "systemctl", "stop", "postgresql"],
                text=True,
                check=True,
            )
            postgres_running = False

        old_dir_stopper = old_data_dir / "fcio_stopper"
        old_dir_stopper.write_text(STOPPER_TEMPLATE.format(pid=os.getpid()))
        shutil.chown(old_dir_stopper, user="postgres")

    if postgres_running:
        get_dbs_cmd = [
            "psql",
            "-qAt",
        ]
    else:
        get_dbs_cmd = [
            old_bin_dir / "postgres",
            "--single",
            "-r",
            "/dev/null",
            "-D",
            old_data_dir,
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
        raise Exit(2)

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

    expected_existing_dbs = {
        "nagios",
        "postgres",
        "root",
        "template0",
        "template1",
        *expected,
    }

    unexpected_dbs = set(existing_dbs) - expected_existing_dbs

    if unexpected_dbs and existing_db_check:
        log.error(
            "upgrade-unexpected-dbs-found",
            _replace_msg=(
                "Found unexpected databases {unexpected_dbs}, "
                "refusing to do the upgrade."
            ),
            unexpected_dbs=unexpected_dbs,
        )
        raise Exit(2)

    postgres_db = existing_dbs["postgres"]
    collate = postgres_db["datcollate"]
    ctype = postgres_db["datctype"]

    new_data_dir_prepared_marker = Path(new_data_dir / "fcio_upgrade_prepared")

    log.info(
        "upgrade-postgres-db",
        _replace_msg=(
            f"Will{'' if upgrade_now else ' prepare'} upgrade from "
            "{old_version} -> {new_version}, using collation {collate} "
            "and ctype {ctype}."
        ),
        upgrade_now=upgrade_now,
        old_version=old_version.value,
        new_version=new_version.value,
        collate=collate,
        ctype=ctype,
    )

    if new_data_dir.exists():
        if (
            new_data_dir_prepared_marker.exists()
            or not existing_new_data_dir_check
        ):
            new_data_dir_mode = new_data_dir.stat().st_mode

            log.info(
                "upgrade-use-existing-new-data-dir",
                new_data_dir=str(new_data_dir),
                owner=new_data_dir.owner(),
                group=new_data_dir.group(),
                mode=oct(new_data_dir_mode)[3:],
            )
            if new_data_dir_mode != 0o040700:
                log.error("upgrade-existing-data-dir-wrong-mode")
        else:
            log.error(
                "upgrade-new-data-dir-unusable",
                _replace_msg=(
                    "New data dir already exists at {new_data_dir} and it "
                    "doesn't have the fcio_upgrade_prepare marker file. "
                    "Refusing to use this directory. Set "
                    "--no-existing-new-data-dir-check if you really want to "
                    "use it."
                ),
                new_data_dir=new_data_dir,
            )
            raise Exit(2)
    else:
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
            postgres_db["datcollate"],
            "--lc-ctype",
            postgres_db["datctype"],
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
            raise Exit(2)

        new_data_dir_prepared_marker.write_text(
            PREPARED_TEMPLATE.format(
                initdb_cmd=initdb_cmd_str, old_data_dir=old_data_dir
            )
        )
        shutil.chown(new_data_dir_prepared_marker, "postgres", "postgres")

    # Do it

    upgrade_cmd = [
        new_bin_dir / "pg_upgrade",
        "--old-datadir",
        old_data_dir,
        "--new-datadir",
        new_data_dir,
        "--old-bindir",
        old_bin_dir,
        "--new-bindir",
        new_bin_dir,
    ]

    if not upgrade_now:
        upgrade_cmd.append("--check")

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
        raise Exit(2)

    if upgrade_now:
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
        new_data_dir_prepared_marker.unlink(missing_ok=True)
        (old_data_dir / "package").unlink(missing_ok=True)
        (old_data_dir / "fcio_stopper").unlink(missing_ok=True)
        nix_gc_root = (
            Path("/nix/var/nix/gcroots/per-user/postgres")
            / "package_{old_version}"
        )
        nix_gc_root.unlink(missing_ok=True)
        Path()

        current_pgdata = get_current_pgdata_from_service()

        if new_data_dir == current_pgdata:
            log.info(
                "upgrade-finished-service-ready",
                _replace_msg=(
                    "Upgrade is finished. You can start the postgresql "
                    "service now."
                ),
            )
        else:
            log.info(
                "upgrade-finished-service-not-ready",
                _replace_msg=(
                    "Upgrade is finished. The postgresql service still refers "
                    "to another data dir: {current_pgdata} and should not be "
                    "started."
                    "Switch to the postgresql{new_version} role now, "
                    "if applicable."
                ),
                current_pgdata=current_pgdata,
                new_version=new_version.value,
            )

    else:
        log.info(
            "upgrade-prepare-finished",
            _replace_msg=(
                "Upgrade preparation finished. If everything looks correct, "
                "run the upgrade by adding --upgrade-now to the command line."
            ),
        )


@app.command()
def list_versions():

    current_pgdata = get_current_pgdata_from_service()
    service_running = is_service_running()

    table = Table(
        show_header=True,
        title="Postgresql versions",
        show_lines=True,
        title_style="bold",
    )

    table.add_column("Version")
    table.add_column("Data Dir Present?")
    table.add_column("Service Running?")
    table.add_column("Migrated To")
    table.add_column("Migrated From")
    table.add_column("Package Known?")
    for version in [v.value for v in PGVersion][:-1]:
        data_dir = Path("/srv/postgresql") / version

        from_link = data_dir / "fcio_migrated_from"
        to_link = data_dir / "fcio_migrated_to"

        table.add_row(
            version,
            str(data_dir) if data_dir.exists() else "-",
            "Yes" if current_pgdata == data_dir and service_running else "-",
            str(to_link.readlink()) if to_link.is_symlink() else "-",
            str(from_link.readlink()) if from_link.is_symlink() else "-",
            "Yes" if (data_dir / "package").exists() else "-",
        )

    rich.print(table)


if __name__ == "__main__":
    app()
