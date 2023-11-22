import os
import traceback
from pathlib import Path
from typing import NamedTuple

import fc.manage.manage
import fc.util.enc
import fc.util.logging
import structlog
from fc.util import nixos
from fc.util.lock import locked
from fc.util.typer_utils import FCTyperApp
from typer import Argument, Exit, Option


class Context(NamedTuple):
    tmpdir: Path
    logdir: Path
    lock_dir: Path
    enc_path: Path
    verbose: bool
    show_trace: bool
    show_caller_info: bool


context: Context


app = FCTyperApp("fc-manage")


@app.command()
def check():
    fc.util.logging.init_logging(
        context.verbose, context.logdir, log_to_console=context.verbose
    )
    log = structlog.get_logger()
    try:
        enc = fc.util.enc.load_enc(log, context.enc_path)
        result = fc.manage.manage.check(log, enc)
    except Exception:
        print("UNKNOWN: Exception occurred while running checks")
        traceback.print_exc()
        raise Exit(3)

    print(result.format_output())
    if result.exit_code:
        raise Exit(result.exit_code)


@app.command()
def dry_activate(
    channel_url: str = Argument(..., help="Channel URL to build."),
    show_trace: bool = Option(
        False,
        help="Nix errors: show detailed location information",
    ),
):
    """Builds system, showing which services would be affected.
    Does not affect the running system.
    """
    fc.util.logging.init_logging(
        context.verbose, context.logdir, log_cmd_output=True
    )
    log = structlog.get_logger()
    unit_changes = fc.manage.manage.dry_activate(
        log=log,
        channel_url=channel_url,
        show_trace=context.show_trace or show_trace,
    )
    unit_change_lines = nixos.format_unit_change_lines(unit_changes)
    if unit_change_lines:
        log.info(
            "fc-manage-dry-run-changes",
            _replace_msg=(
                "The following unit changes would be applied when "
                "changing to this system:"
            ),
            _output="\n".join(unit_change_lines),
        )
    else:
        log.info(
            "fc-manage-dry-run-no-changes",
            _replace_msg="Changing to this system would not affect units.",
        )


@app.command(name="switch")
def switch_cmd(
    update_enc_data: bool = Option(
        False,
        "--update-enc",
        "-e",
        help="Fetch inventory data from directory before building the system.",
    ),
    update_channel: bool = Option(
        False,
        "--update-channel",
        "-c",
        help="Fetch nixpkgs channel before building the system.",
    ),
    lazy: bool = Option(
        False,
        help="Skip the system activation script if system is unchanged.",
    ),
    show_trace: bool = Option(
        False,
        help="Nix errors: show detailed location information",
    ),
):
    """Builds the system configuration and switches to it."""
    fc.util.logging.init_logging(
        context.verbose, context.logdir, log_cmd_output=True
    )
    log = structlog.get_logger()
    log.info(
        "fc-manage-start", _replace_msg="fc-manage started with PID: {pid}"
    )

    with locked(log, context.lock_dir):
        if update_enc_data:
            fc.util.enc.update_enc(log, context.tmpdir, context.enc_path)

        enc = fc.util.enc.load_enc(log, context.enc_path)

        keep_cmd_output = fc.manage.manage.initial_switch_if_needed(log, enc)

        try:
            if update_channel:
                keep_cmd_output |= fc.manage.manage.switch_with_update(
                    log=log,
                    enc=enc,
                    lazy=lazy,
                    show_trace=context.show_trace or show_trace,
                )
            else:
                keep_cmd_output |= fc.manage.manage.switch(
                    log=log,
                    enc=enc,
                    lazy=lazy,
                    show_trace=context.show_trace or show_trace,
                )
        except nixos.ChannelException:
            raise Exit(2)

        if not keep_cmd_output:
            fc.util.logging.drop_cmd_output_logfile(log)

    log.info("fc-manage-succeeded")


@app.command(name="update-enc")
def update_enc_cmd():
    """
    Fetches inventory data from directory.
    """

    fc.util.logging.init_logging(context.verbose, context.logdir)
    log = structlog.get_logger()

    log.info(
        "fc-manage-start", _replace_msg="fc-manage started with PID: {pid}"
    )

    with locked(log, context.lock_dir):
        fc.util.enc.update_enc(log, context.tmpdir, context.enc_path)

    log.info("fc-manage-succeeded")


@app.callback(invoke_without_command=True, no_args_is_help=True)
def fc_manage(
    switch: bool = Option(
        False, "--build", "-b", help="(legacy flag) Build and switch system."
    ),
    switch_with_update: bool = Option(
        False,
        "--channel",
        "-c",
        help="(legacy flag) Update channel, build, switch.",
    ),
    update_enc_data: bool = Option(
        False, "--directory", "-e", help="(legacy flag) Update inventory data."
    ),
    verbose: bool = Option(
        False,
        "--verbose",
        "-v",
        help=(
            "Show debug logging output. By default, only info and higher "
            "levels are shown."
        ),
    ),
    show_caller_info: bool = Option(
        False,
        help="Show where a logging function was called (file/function/line).",
    ),
    show_trace: bool = Option(
        False,
        help="Nix errors: show detailed location information",
    ),
    logdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log",
        help="Directory for log files, expects a fc-agent subdirectory there.",
    ),
    tmpdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/tmp",
        help="Directory where temporary files should be placed.",
    ),
    lock_dir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/run/lock",
        help="Directory where the lock file for exclusive operations should be "
        "placed.",
    ),
    enc_path: Path = Option(
        dir_okay=False,
        readable=True,
        default="/etc/nixos/enc.json",
        help="Path to enc.json",
    ),
):
    """
    System management command for getting inventory data and building the
    system configuration.
    Supports old-style action flags (-b, -c, -e) and new-style sub commands.
    The new sub commands 'fc-manage switch' and 'fc-manage update-enc' should be
    preferred.

    Legacy flags: The -e flag can be used separately or be combined with -c
    or -b.
    """
    global context

    if not (switch or switch_with_update or update_enc_data):
        # no action option given, new style call
        context = Context(
            tmpdir=tmpdir,
            logdir=logdir,
            lock_dir=lock_dir,
            enc_path=enc_path,
            verbose=verbose,
            show_trace=show_trace,
            show_caller_info=show_caller_info,
        )
        return

    # legacy call
    fc.util.logging.init_logging(
        verbose, logdir, log_cmd_output=switch or switch_with_update
    )
    log = structlog.get_logger()

    log.info(
        "fc-manage-start",
        _replace_msg="fc-manage started with PID: {pid}",
        legacy_call=True,
    )

    with locked(log, lock_dir):
        if update_enc_data:
            fc.util.enc.update_enc(log, tmpdir, enc_path)

        enc = fc.util.enc.load_enc(log, enc_path)
        keep_cmd_output = False

        if switch or switch_with_update:
            keep_cmd_output = fc.manage.manage.initial_switch_if_needed(
                log, enc
            )

        try:
            if switch_with_update:
                keep_cmd_output |= fc.manage.manage.switch_with_update(
                    log=log,
                    enc=enc,
                    lazy=False,
                    show_trace=show_trace,
                )
            elif switch:
                keep_cmd_output |= fc.manage.manage.switch(
                    log=log,
                    enc=enc,
                    lazy=False,
                    show_trace=show_trace,
                )
        except nixos.ChannelException:
            raise Exit(2)

        if not keep_cmd_output:
            fc.util.logging.drop_cmd_output_logfile(log)

    log.info("fc-manage-succeeded", legacy_call=True)


if __name__ == "__main__":
    app()
