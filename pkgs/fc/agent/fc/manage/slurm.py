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
import pyslurm


class Context(NamedTuple):
    logdir: Path
    verbose: bool


app = Typer(pretty_exceptions_show_locals=False)
context: Context


@app.callback(no_args_is_help=True)
def fc_slurm(
    verbose: bool = Option(
        False, "--verbose", "-v", help="Show debug messages and code locations."
    ),
    logdir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log/fc-agent/slurm",
        help="Directory for log files.",
    ),
):
    global context

    context = Context(
        logdir=logdir,
        verbose=verbose,
    )

    init_logging(verbose, syslog_identifier="fc-slurm")


@app.command(
    help="Drain this node and wait for completion",
)
def drain_and_wait(
    timeout: int = Option(
        default=300, help="Wait for seconds for every job to finish."
    ),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()

    log.debug("drain-start")
    log.debug("drain-finished")


@app.command()
def ready():
    log = structlog.get_logger()


@app.command(help="")
def check():
    log = structlog.get_logger()
