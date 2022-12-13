import os
import rich
import socket
import structlog
from pathlib import Path
from typer import Option, Typer
from typing import NamedTuple, Optional

import fc.util.slurm
from fc.util.logging import init_logging


class Context(NamedTuple):
    logdir: Path
    verbose: bool


app = Typer(
    pretty_exceptions_show_locals=bool(os.getenv("FC_AGENT_SHOW_LOCALS", False))
)
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

    init_logging(verbose, logdir, syslog_identifier="fc-slurm")


@app.command(
    help="Drain this node and wait for completion",
)
def drain(
    timeout: int = Option(
        default=300, help="Wait for seconds for every job to finish."
    ),
    reason: str = Option(
        default="fc-slurm", help="reason for draining the node"
    ),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.drain(log, hostname, timeout, reason, nothing_to_do_is_ok)


@app.command(
    help="Drain, wait for completion and down this node",
)
def drain_and_down(
    timeout: int = Option(
        default=300, help="Wait for seconds for every job to finish."
    ),
    reason: str = Option(
        default="fc-slurm", help="reason for draining the node"
    ),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.drain(log, hostname, timeout, reason, nothing_to_do_is_ok)
    fc.util.slurm.down(log, hostname, nothing_to_do_is_ok, reason)


@app.command()
def down(
    nothing_to_do_is_ok: Optional[bool] = False,
    reason: str = Option(
        default="fc-slurm", help="reason for downing the node"
    ),
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.down(log, hostname, nothing_to_do_is_ok, reason)


@app.command()
def ready(
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.ready(log, hostname, nothing_to_do_is_ok)


@app.command(help="")
def check():
    log = structlog.get_logger()
    hostname = socket.gethostname()
    node_info = fc.util.slurm.get_node_info(hostname)
    rich.print(node_info)
