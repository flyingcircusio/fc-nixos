from pathlib import Path
from typing import NamedTuple, Optional

import structlog
import typer
from fc.maintenance.activity.reboot import RebootActivity
from fc.maintenance.lib.shellscript import ShellScriptActivity
from fc.maintenance.maintenance import (
    request_reboot_for_cpu,
    request_reboot_for_kernel,
    request_reboot_for_memory,
    request_reboot_for_qemu,
    request_update,
)
from fc.maintenance.reqmanager import (
    DEFAULT_CONFIG_FILE,
    DEFAULT_SPOOLDIR,
    ReqManager,
)
from fc.maintenance.request import Request
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
    show_caller_info: bool


context: Context
rm: ReqManager


@app.callback(no_args_is_help=True)
def main(
    verbose: bool = Option(
        False,
        "--verbose",
        "-v",
        help=(
            "Show debug and trace (Nix command) output. By default, only log "
            "levels info and higher are shown."
        ),
    ),
    show_caller_info: bool = Option(
        False,
        "--show-caller-info",
        help="Show where a logging function was called (file/function/line).",
    ),
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
        show_caller_info=show_caller_info,
    )

    init_logging(
        context.verbose, context.logdir, show_caller_info=show_caller_info
    )

    rm = ReqManager(
        spooldir=spooldir,
        enc_path=enc_path,
        config_file=config_file,
        log=log,
    )


@app.command()
def run(run_all_now: bool = False, force_run: bool = False):
    """
    Run all maintenance activity requests that are due.

    Note that this does not schedule pending requests like running the script without
    arguments in the past did. Run the schedule subcommand if you want to ensure that we
    know execution times for all existing requests and have recent information from the
    directory about requests that have been moved to another start date.

    If you want to immediately execute all pending requests regardless if they
    are due now, specify --run-all-now.

    Before requests are executed, the system is put into maintenance mode. Then,
    maintenance enter commands are executed which are defined in the agent config file.

    If a command returns exit code 75 (EXIT_TEMPFAIL), no requests will be run and the
    machine will stay in maintenance mode. The next call will retry the activities if
    they are still runnable.

    If a command returns exit code 69 (EXIT_POSTPONE), all runnable requests are
    put into the `postpone` state and the machine leaves maintenance mode.

    If you still want to execute requests even if a maintenance enter command returned
    with EXIT_TEMPFAIL or EXIT_POSTPONE, add the --force-run flag.

    After executing all runnable requests, requests that want to be postponed
    are postponed (they get a new execution time) and finished requests
    (successful or failed permanently) moved from the current request to the
    archive directory.
    """
    log.info("fc-maintenance-run-start")
    with rm:
        rm.update_states()
        rm.execute(run_all_now, force_run)
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
def run_script(comment: str, script: str, estimate: Optional[str] = None):
    """Request to run a script."""
    request = Request(ShellScriptActivity(script), estimate, comment)
    with rm:
        rm.scan()
        rm.add(request)


@request_app.command()
def reboot(comment: Optional[str] = None, cold_reboot: bool = False):
    """Request a reboot."""
    action = "poweroff" if cold_reboot else "reboot"
    request = Request(RebootActivity(action), comment=comment)
    with rm:
        rm.scan()
        rm.add(request)


@request_app.command()
def system_properties():
    """Request reboot for changed system properties.
    Runs applicable checks for the machine type (virtual/physical).

    * Physical: kernel

    * Virtual: kernel, memory, number of CPUs, qemu version

    """
    log.info("fc-maintenance-system-properties-start")
    enc = load_enc(log, context.enc_path)

    with rm:
        rm.scan()

        if enc["parameters"]["machine"] == "virtual":
            rm.add(request_reboot_for_memory(log, enc))
            rm.add(request_reboot_for_cpu(log, enc))
            rm.add(request_reboot_for_qemu(log))

        rm.add(request_reboot_for_kernel(log))
        log.info("fc-maintenance-system-properties-finished")


@request_app.command()
def update():
    """Request a system update.

    Builds the system and prepares the update to be run in a maintenance
    window by default.

    Acquires an exclusive lock because this shouldn't be run concurrently
    with more invocations of the update command or other commands (from
    fc-manage) that potentially modify the system.
    """
    log.info("fc-maintenance-update-start")
    enc = load_enc(log, context.enc_path)
    init_command_logging(log, context.logdir)

    with rm:
        rm.scan()
        current_requests = rm.requests.values()

    with locked(log, context.lock_dir):
        try:
            request = request_update(log, enc, current_requests)
        except nixos.ChannelException:
            raise Exit(2)

    with rm:
        request = rm.add(request)

    if request is None:
        drop_cmd_output_logfile(log)

    log.info("fc-maintenance-update-finished")


if __name__ == "__main__":
    app()
