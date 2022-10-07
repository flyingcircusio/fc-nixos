import json
import os
import shutil
import traceback
from pathlib import Path
from typing import List, NamedTuple, Optional

import fc.util.postgresql
import rich
import structlog
from fc.util.logging import init_logging
from fc.util.postgresql import PGVersion
from rich.table import Table
from typer import Exit, Option, Typer, confirm, echo

STOPPER_TEMPLATE = """\
A fc-postgresql upgrade command is running with PID {pid}, postgresql service
won't start with this file present. Remove this if you really want to start
the service with this data dir.
"""


class Context(NamedTuple):
    logdir: Path
    verbose: bool
    pg_data_root: Path


app = Typer()
context: Context


def stop_pg(log, old_data_dir: Path, stop: bool):
    postgres_running = fc.util.postgresql.is_service_running()
    if postgres_running and stop is None:
        stop = confirm(
            "Postgresql must be stopped for the data migration but it is still "
            "running. Can I stop it now?"
        )
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
        fc.util.postgresql.run(
            ["sudo", "systemctl", "stop", "postgresql"],
            text=True,
            check=True,
        )
        postgres_running = False
    old_dir_stopper = old_data_dir / "fcio_stopper"
    old_dir_stopper.write_text(STOPPER_TEMPLATE.format(pid=os.getpid()))
    shutil.chown(old_dir_stopper, user="postgres")
    return postgres_running


@app.callback(no_args_is_help=True)
def fc_postgresql(
    verbose: bool = Option(
        False, "--verbose", "-v", help="Show debug messages and code locations."
    ),
    logdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log/fc-agent/postgresql",
        help="Directory for log files.",
    ),
    pg_data_root: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/srv/postgresql",
        help=(
            "Directory where PG data dirs are stored. subdirectories are "
            "expected to have the PostgreSQL major version as name"
        ),
    ),
):
    global context

    context = Context(
        logdir=logdir,
        verbose=verbose,
        pg_data_root=pg_data_root,
    )

    init_logging(verbose, syslog_identifier="fc-postgresql")


@app.command(
    no_args_is_help=True,
    help="Major version upgrade using pg_upgrade.",
)
def upgrade(
    new_version: PGVersion = Option(
        show_choices=True,
        default=None,
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
    stop: Optional[bool] = Option(default=None),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()

    log.debug("upgrade-start")

    if not (new_data_dir and new_bin_dir):
        if new_version is None:
            echo(
                "If PG version is not specified, both new-data-dir and "
                "new-bin-dir must be specified instead!"
            )
            raise Exit(2)

        new_bin_dir = fc.util.postgresql.build_new_bin_dir(
            log, context.pg_data_root, new_version
        )
        new_data_dir = context.pg_data_root / new_version.value

    try:
        old_data_dir = fc.util.postgresql.find_old_data_dir(
            log, context.pg_data_root, new_version
        )
    except fc.util.postgresql.MultipleOldDirsFound as e:
        log.error(
            "upgrade-multiple-old-dirs-found",
            old_data_dirs={str(d) for d in e.found_dirs},
            _replace_msg=(
                "Found multiple old data dirs which could be upgraded: "
                "{old_data_dirs}. Remove old data dirs which are not "
                "needed anymore and try again."
            ),
        )
        raise Exit(2)

    exit_on_no_old_data_dir(log, old_data_dir, nothing_to_do_is_ok)

    try:
        fc.util.postgresql.prepare_upgrade(
            log,
            old_data_dir,
            new_version,
            new_bin_dir,
            new_data_dir,
            expected_databases=expected if existing_db_check else None,
        )
    except fc.util.postgresql.NewDataDirUnusable as e:
        log.error(
            "upgrade-new-data-dir-unusable",
            _replace_msg=(
                "New data dir already exists at {new_data_dir} and it "
                "doesn't have the fcio_upgrade_prepare marker file. "
                "Refusing to use this directory."
            ),
            new_data_dir=e.data_dir,
        )
        raise Exit(2)
    except fc.util.postgresql.UnexpectedDatabasesFound as e:
        cmdline_hint = " ".join("--expected " + db for db in e.unexpected_dbs)
        log.error(
            "prepare-autoupgrade-unexpected-dbs",
            _replace_msg=(
                "Found unexpected databases {unexpected_dbs}, "
                "Refusing to run the upgrade. Add to the the command line: "
                + cmdline_hint
            ),
            unexpected_dbs=e.unexpected_dbs,
        )
        raise Exit(2)

    if upgrade_now:

        stop_pg(log, old_data_dir, stop)

        fc.util.postgresql.run_pg_upgrade(
            log,
            new_bin_dir,
            new_data_dir,
            old_data_dir,
        )

        current_pgdata = fc.util.postgresql.get_current_pgdata_from_service()

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
                    "started. Switch to the postgresql{new_version} role now, "
                    "if applicable."
                ),
                current_pgdata=current_pgdata,
                new_version=new_version.value,
            )
    else:
        fc.util.postgresql.run_pg_upgrade_check(
            log,
            new_bin_dir,
            new_data_dir,
            old_data_dir,
        )

        log.info(
            "upgrade-prepare-finished",
            _replace_msg=(
                "Upgrade preparation finished. If everything looks correct, "
                "run the upgrade by adding --upgrade-now to the command line."
            ),
        )


def exit_on_no_old_data_dir(log, old_data_dir, nothing_to_do_is_ok):
    if old_data_dir is None:
        if nothing_to_do_is_ok:
            log.info(
                "upgrade-nothing-to-do",
                _replace_msg=(
                    "No old data directory found that could be migrated."
                ),
            )
            raise Exit()
        else:
            log.error(
                "upgrade-no-old-dirs-found",
                _replace_msg=(
                    "Couldn't find an eligible data dir for upgrading in "
                    f"{context.pg_data_root}. Data dirs must have a symlink "
                    "called 'package' pointing to the corresponding postgresql "
                    "package."
                ),
            )
            raise Exit(2)


@app.command()
def check_autoupgrade_unexpected_dbs(
    config: Path = Option(
        exists=True,
        file_okay=True,
        dir_okay=False,
        default="/etc/local/postgresql/autoupgrade.json",
    ),
):
    with open(config) as f:
        autoupgrade_config = json.load(f)
        expected_databases = set(autoupgrade_config["expected_databases"])

    log = structlog.get_logger()

    data_dir = fc.util.postgresql.get_current_pgdata_from_service()
    try:
        fc.util.postgresql.get_existing_dbs(
            log,
            data_dir,
            postgres_running=True,
            expected_dbs=expected_databases,
        )
    except fc.util.postgresql.UnexpectedDatabasesFound as e:
        print(
            f"WARNING: autoupgrade will not work, unexpected databases found:"
            f" {e.unexpected_dbs}, "
            f"expected only: {expected_databases}"
        )
        raise Exit(1)
    except Exception:
        print("UNKNOWN: getting existing databases failed with an exception:")
        traceback.print_exc()
        raise Exit(3)

    print(f"OK: no unexpected databases found that would block autoupgrade.")


@app.command(help="Prep data dir for autoupgrade")
def prepare_autoupgrade(
    config: Path = Option(
        exists=True,
        file_okay=True,
        dir_okay=False,
        default="/etc/local/postgresql/autoupgrade.json",
    ),
    new_version: PGVersion = Option(
        ...,
        prompt=True,
        show_choices=True,
        help="PostgreSQL version to upgrade to.",
    ),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    with open(config) as f:
        autoupgrade_config = json.load(f)
        expected_databases = autoupgrade_config["expected_databases"]

    log = structlog.get_logger()

    new_bin_dir = fc.util.postgresql.build_new_bin_dir(
        log, context.pg_data_root, new_version
    )
    new_data_dir = context.pg_data_root / new_version.value

    if fc.util.postgresql.is_service_running():
        current_data_dir = fc.util.postgresql.get_current_pgdata_from_service()
        current_service_version = (
            fc.util.postgresql.get_pg_version_from_data_dir(
                log, current_data_dir
            )
        )

        if new_version == current_service_version:
            log.info(
                "prepare-autoupgrade-requested-version-current",
                version=new_version,
                _replace_msg=(
                    "No upgrade needed: the currently running postgresql "
                    "service already uses the requested version {version}"
                ),
            )
            raise Exit()
    else:
        log.warn(
            "prepare-autoupgrade-pg-not-running",
            _replace_msg=(
                "The postgresql service is not running. You might want "
                "to check its status. This can happen when autoupgrade "
                "refused to do an upgrade. Continuing."
            ),
        )

    try:
        old_data_dir = fc.util.postgresql.find_old_data_dir(
            log, context.pg_data_root, new_version
        )
    except fc.util.postgresql.MultipleOldDirsFound as e:
        log.error(
            "prepare-autoupgrade-multiple-old-dirs-found",
            old_data_dirs={str(d) for d in e.found_dirs},
            _replace_msg=(
                "Found multiple old data dirs which could be upgraded: "
                "{old_data_dirs}. Delete old data dirs which are not "
                "needed anymore and try again."
            ),
        )
        raise Exit(2)

    exit_on_no_old_data_dir(log, old_data_dir, nothing_to_do_is_ok)

    try:
        fc.util.postgresql.prepare_upgrade(
            log,
            old_data_dir=old_data_dir,
            new_version=new_version,
            new_bin_dir=new_bin_dir,
            new_data_dir=new_data_dir,
            expected_databases=expected_databases,
        )
    except fc.util.postgresql.NewDataDirUnusable as e:
        log.error(
            "prepare-autoupgrade-new-data-dir-unusable",
            _replace_msg=(
                "New data dir already exists at {new_data_dir} and it "
                "doesn't have the 'fcio_upgrade_prepare' marker file. "
                "Refusing to use this directory."
            ),
            new_data_dir=e.data_dir,
        )
        raise Exit(2)
    except fc.util.postgresql.UnexpectedDatabasesFound as e:
        log.error(
            "prepare-autoupgrade-unexpected-dbs",
            _replace_msg=(
                "Found unexpected databases {unexpected_dbs}, autoupgrade will "
                "refuse to run the upgrade. Add databases to the NixOS option "
                "'flyingcircus.postgresql.autoUpgrade.expectedDatabases'."
            ),
            unexpected_dbs=e.unexpected_dbs,
        )
        raise Exit(2)

    fc.util.postgresql.run_pg_upgrade_check(
        log,
        new_bin_dir=new_bin_dir,
        new_data_dir=new_data_dir,
        old_data_dir=old_data_dir,
    )

    log.info(
        "prepare-autoupgrade-finished",
        _replace_msg="Preparation completed, autoupgrade should run fine.",
    )


LIST_VERSION_HELP = """\
Data dirs and migration state.

## Fields

*Version*

Major version of PostgreSQL. All versions available on the current platform
version are shown.

*Data Dir*

Path to data dir if it exists for this version.

*Service Running?*

`Yes` if postgresql.service is running and is using this version.

*Migrated To*

Target data dir where data has been migrated to. Data dirs with which have
been migrated must not be used anymore.

*Migrated From*

Source data dir where data has been migrated from.

*Package Link Present?*

`Yes` if the `package` link in data dir is valid. The link points to the
PostgreSQL version that is or has been used for this data dir. The link is
needed to upgrade to a newer version as pg_upgrade needs the old binaries to
work. fc-postgresql upgrade and auto-upgrades will fail if this is missing.

*Prepared As Upgrade Target?*

`Yes` if data dir is prepared to be used as target for an upgrade migration.
This means that `fc-postgresql prepare-autoupgrade` or `fc-postgresql
upgrade` without `--upgrade-now` has created this data dir with an empty
cluster.

"""


@app.command(help=LIST_VERSION_HELP)
def list_versions():

    current_pgdata = fc.util.postgresql.get_current_pgdata_from_service()
    service_running = fc.util.postgresql.is_service_running()

    table = Table(
        show_header=True,
        title="Postgresql versions",
        show_lines=True,
        title_style="bold",
    )

    table.add_column("Version")
    table.add_column("Data Dir")
    table.add_column("Service Running?")
    table.add_column("Migrated To")
    table.add_column("Migrated From")
    table.add_column("Package Link Present?")
    table.add_column("Prepared As Upgrade Target?")
    for version in [v.value for v in PGVersion]:
        data_dir = context.pg_data_root / version

        from_link = data_dir / "fcio_migrated_from"
        to_link = data_dir / "fcio_migrated_to"
        prepared_marker = data_dir / "fcio_upgrade_prepared"

        table.add_row(
            version,
            str(data_dir) if data_dir.exists() else "-",
            "Yes" if current_pgdata == data_dir and service_running else "-",
            str(to_link.readlink()) if to_link.is_symlink() else "-",
            str(from_link.readlink()) if from_link.is_symlink() else "-",
            "Yes" if (data_dir / "package").exists() else "-",
            "Yes" if prepared_marker.exists() else "-",
        )

    rich.print(table)


if __name__ == "__main__":
    app()
