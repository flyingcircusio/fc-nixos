import os
import time
from pathlib import Path
from typing import NamedTuple

import fc.manage.manage
import fc.util.enc
import fc.util.keepalived
import fc.util.logging
import structlog
from fc.maintenance.state import EXIT_TEMPFAIL
from fc.util.keepalived import (
    KEEPALIVED_STATE_FILE,
    MAINT_MARKER_FILE,
    KeepalivedState,
    KeepalivedStateError,
)
from fc.util.nixos import Specialisation
from fc.util.typer_utils import FCTyperApp
from typer import Argument, Exit, Option

app = FCTyperApp("fc-keepalived")


class Context(NamedTuple):
    logdir: Path
    lock_dir: Path


context: Context


@app.callback()
def fc_keepalived(
    logdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log",
        help="Directory for log files, expects a fc-agent subdirectory there.",
    ),
    lock_dir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/run/lock",
        help="Directory where the lock file for exclusive operations should be "
        "placed.",
    ),
):
    global context
    context = Context(
        logdir=logdir,
        lock_dir=lock_dir,
    )

    fc.util.logging.init_logging(
        verbose=True, logdir=logdir, log_to_console=True
    )


@app.command()
def check():
    """
    Checks keepalived maintenance state controlled by this script.

    Two files are checked:
    - maintenance marker file (is modified by fc-keepalived enter-maintenance
      and leave-maintenance)
    - keepalived state file (is modified by fc-keepalived notify).

    XXX: turn this into a real Sensu check. At the moment, it just displays
    log messages as a side effect of get_state().
    """
    log = structlog.get_logger()
    fc.util.keepalived.get_state(log)


@app.command()
def enter_maintenance():
    log = structlog.get_logger()
    log.info("enter-maintenance")

    try:
        state = fc.util.keepalived.get_state(log)
    except KeepalivedStateError:
        log.warn("maint-skip")
        raise Exit(EXIT_TEMPFAIL)

    # No need to change the maintenance marker when the router is in a fault
    # or stop state, just skip maintenance and signal a temporary failure.
    if state in (KeepalivedState.FAULT, KeepalivedState.STOP):
        log.warn("maint-skip", state=state)
        raise Exit(EXIT_TEMPFAIL)

    try:
        # Reduces priority of keepalived by 20, should trigger a switchover to
        # another router when we are primary here at the moment.
        MAINT_MARKER_FILE.write_text("1")
        elapsed = 0
        while state == KeepalivedState.MASTER:
            if elapsed > 60:
                log.warn("switchover-timeout", elapsed=elapsed, state=state)
                raise Exit(EXIT_TEMPFAIL)
            log.debug("wait-for-backup-state", state=state, elapsed=elapsed)
            time.sleep(1)
            elapsed += 1
            state_content = KEEPALIVED_STATE_FILE.read_text()
            try:
                state = KeepalivedState(state_content)
            except ValueError:
                log.error(
                    "unexpected-state-file-content",
                    state_content=state_content,
                )
                raise Exit(EXIT_TEMPFAIL)

        if state == KeepalivedState.BACKUP:
            log.debug("backup-state-reached")
        else:
            log.warn(
                "unexpected-state-after-switch",
                expected=KeepalivedState.BACKUP,
                actual=state,
            )
            raise Exit(EXIT_TEMPFAIL)

    except Exception:
        MAINT_MARKER_FILE.write_text("0")
        log.info("exception-reset-maint-marker")
        raise

    log.info("enter-maintenance-finished")


@app.command()
def leave_maintenance():
    log = structlog.get_logger()
    log.debug("leave-maintenance-start")
    try:
        state = fc.util.keepalived.get_state(log)
    except KeepalivedStateError:
        # get_state() has already logged the error.
        # There's something wrong with the state/maintenance files, but we can
        # still go on and leave maintenance.
        state = None
    log.info("reset-maint-marker")
    MAINT_MARKER_FILE.write_text("0")
    log.info("leave-maintenance-finished", state=state)


@app.command()
def notify(
    new_state: KeepalivedState = Argument(..., help="New keepalived state"),
):
    """
    Triggers a system switch when keepalived state changes.
    To be used as keepalived notify script.


    """
    log = structlog.get_logger()
    log.debug("notify", new_state=new_state)

    if new_state == KeepalivedState.MASTER:
        specialisation = "primary"
    else:
        specialisation = Specialisation.BASE_CONFIG

    fc.manage.manage.switch_to_configuration(
        log=log,
        specialisation=specialisation,
        lock_dir=context.lock_dir,
        lazy=True,
    )

    KEEPALIVED_STATE_FILE.write_text(new_state.value)

    log.info("notify-finished")


if __name__ == "__main__":
    app()
