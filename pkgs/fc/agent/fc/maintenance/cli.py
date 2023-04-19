import sys
from pathlib import Path
from typing import NamedTuple, Optional

import structlog
import typer
from fc.maintenance.activity.update import UpdateActivity
from fc.maintenance.lib.reboot import RebootActivity
from fc.maintenance.lib.shellscript import ShellScriptActivity
from fc.maintenance.reqmanager import (
    DEFAULT_CONFIG_FILE,
    DEFAULT_SPOOLDIR,
    ReqManager,
)
from fc.maintenance.request import Request
from fc.maintenance.system_properties import (
    request_reboot_for_cpu,
    request_reboot_for_kernel,
    request_reboot_for_memory,
    request_reboot_for_qemu,
)
from fc.manage.manage import prepare_switch_in_maintenance, switch_with_update
from fc.util import nixos
from fc.util.enc import load_enc
from fc.util.lock import locked
from fc.util.logging import (
    drop_cmd_output_logfile,
    init_command_logging,
    init_logging,
)
from typer import Argument, Exit, Option, Typer

app = Typer(pretty_exceptions_show_locals=False)
log = structlog.get_logger()


class Context(NamedTuple):
    config_file: Path
    enc_path: Path
    logdir: Path
    lock_dir: Path
    spooldir: Path
    verbose: bool


context: Context
rm: ReqManager


@app.callback(no_args_is_help=True)
def main(
    verbose: bool = False,
    spooldir: Path = Option(
        file_okay=False,
        writable=True,
        default=DEFAULT_SPOOLDIR,
        help="Directory to store maintenance request files.",
    ),
    logdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log",
        help="Directory for log files. Must have a fc-agent subdirectory.",
    ),
    lock_dir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/run/lock",
        help="Directory where the lock file for exclusive operations should be "
        "placed.",
    ),
    config_file: Path = Option(
        dir_okay=False,
        readable=True,
        default=DEFAULT_CONFIG_FILE,
        help="Path to the agent config file.",
    ),
    enc_path: Path = Option(
        dir_okay=False,
        readable=True,
        default="/etc/nixos/enc.json",
        help="Path to enc.json",
    ),
):
    """
    Manage maintenance requests for this machine.
    """
    global context
    global rm

    context = Context(
        config_file=config_file,
        enc_path=enc_path,
        logdir=logdir,
        lock_dir=lock_dir,
        spooldir=spooldir,
        verbose=verbose,
    )

    init_logging(context.verbose, context.logdir)

    rm = ReqManager(
        spooldir=spooldir,
        enc_path=enc_path,
        config_file=config_file,
        log=log,
    )


@app.command()
def run(run_all_now: bool = False):
    """
    Run all requests that are due.

    Note that this does not schedule pending requests like
    running the script without arguments in the past did.
    Run the schedule subcommand if you want to ensure
    that we know execution times for all existing requests and have recent
    information from the directory about requests that have been moved to
    another start date.

    If you want to immediately execute all pending requests regardless if they
    are due now, specify --run-all-now.

    After executing all runnable requests, requests that want to be postponed
    are postponed (they get a new execution time) and finished requests
    (successful or failed permanently) moved from the current request to the
    archive directory.

    Executing, postponing and archiving can be disabled using their respective
    flags for testing and debugging purposes, for example.
    """
    log.info("fc-maintenance-run-start")
    with rm:
        rm.execute(run_all_now)
        rm.postpone()
        rm.archive()
    log.info("fc-maintenance-run-finished")


@app.command(name="list")
def list_cmd():
    """
    List active maintenance requests.
    """
    with rm:
        rm.list()


@app.command()
def show(request_id: Optional[str] = Argument(None), dump_yaml: bool = False):
    """Show details for a request."""
    with rm:
        rm.show(request_id, dump_yaml)


@app.command()
def delete(request_id: str, archive: bool = True):
    """
    Delete a request by request ID.

    See the output of the `list` subcommand for available request IDs.
    """
    with rm:
        rm.delete(request_id)
        if archive:
            rm.archive()


@app.command()
def schedule():
    """Schedule all requests."""
    log.info("fc-maintenance-schedule-start")
    with rm:
        rm.schedule()
    log.info("fc-maintenance-schedule-finished")


# Request subcommands

request_app = typer.Typer(pretty_exceptions_show_locals=False)
app.add_typer(request_app, name="request")


@request_app.callback(no_args_is_help=True)
def request_main():
    """
    Create a new request (see sub commands).
    """


@request_app.command(name="script")
def run_script(comment: str, script: str, estimate: str = "10m"):
    """Request to run a script."""
    request = Request(ShellScriptActivity(script), estimate, comment=comment)
    with rm:
        rm.scan()
        rm.add(request)


@request_app.command()
def reboot(comment: Optional[str] = None, cold_reboot: bool = False):
    """Request a reboot."""
    action = "poweroff" if cold_reboot else "reboot"
    default_comment = "Scheduled {}".format(
        "cold boot" if cold_reboot else "reboot"
    )
    request = Request(
        RebootActivity(action),
        900 if cold_reboot else 600,
        comment if comment else default_comment,
    )
    with rm:
        rm.scan()
        rm.add(request)


@request_app.command()
def system_properties():
    """Request reboot for changed sys properties.
    Runs applicable checks for the machine type (virtual/physical).

    * Physical: kernel

    * Virtual: kernel, memory, number of CPUs, qemu version

    """
    log.info("fc-maintenance-system-properties-start")
    enc = load_enc(log, context.enc_path)

    with rm:
        rm.scan()

        if enc["parameters"]["machine"] == "virtual":
            rm.add(request_reboot_for_memory(enc))
            rm.add(request_reboot_for_cpu(enc))
            rm.add(request_reboot_for_qemu())

        rm.add(request_reboot_for_kernel())
        log.info("fc-maintenance-system-properties-finished")


@request_app.command()
def update(
    run_now: bool = Option(
        default=False, help="do update now instead of scheduling a request"
    )
):
    """Request a system update.

    Builds the system and prepares the update to be run in a maintenance
    window by default. To activate the update immediately, pass the
    --run-now option.

    Acquires an exclusive lock because this shouldn't be run concurrently
    with more invocations of the update command or other commands (from
    fc-manage) that
    potentially modify the system."""
    init_command_logging(log, context.logdir)
    log.info("fc-maintenance-update-start")
    enc = load_enc(log, context.enc_path)

    with locked(log, context.lock_dir):
        try:
            if run_now:
                keep_cmd_output = switch_with_update(log, enc, lazy=True)
            else:
                keep_cmd_output = prepare_switch_in_maintenance(log, enc)
        except nixos.ChannelException:
            raise Exit(2)

    if not keep_cmd_output:
        drop_cmd_output_logfile(log)

    log.info("fc-maintenance-update-finished")


@request_app.command()
def update_with_update_activity(
    channel_url: str = Argument(..., help="channel URL to update to"),
    run_now: bool = Option(
        default=False, help="do update now instead of scheduling a request"
    ),
    dry_run: bool = Option(
        default=False, help="do nothing, just show activity"
    ),
):
    """(Experimental) Prepare an UpdateActivity or execute it now."""

    activity = UpdateActivity.from_system_if_changed(channel_url)

    if activity is None:
        log.warn(
            "update-skip",
            _replace_msg="Channel URL unchanged, skipped.",
            activity=activity,
        )
        sys.exit(1)

    activity.prepare(dry_run)

    # possible short-cut: built system is the same
    # => we can skip requesting maintenance and set the new channel directly

    if run_now:
        log.info(
            "update-run-now",
            _replace_msg="Run-now mode requested, running the update now.",
        )
        activity.run()

    elif dry_run:
        log.info(
            "update-dry-run",
            _replace_msg=(
                "Update prediction was successful. This would be applied by "
                "the update:"
            ),
            _output=activity.changelog,
        )
    else:
        with rm:
            rm.scan()
            rm.add(Request(activity, 600, activity.changelog))
        log.info(
            "update-prepared",
            _replace_msg=(
                "Update preparation was successful. This will be applied in a "
                "maintenance window:"
            ),
            _output=activity.changelog,
        )
