import os
import socket
from pathlib import Path
from typing import NamedTuple, Optional

import fc.util.kubernetes
import structlog
from fc.maintenance.state import EXIT_TEMPFAIL
from fc.util.directory import directory_connection
from fc.util.logging import init_logging
from fc.util.typer_utils import FCTyperApp
from rich import print
from typer import Exit, Option, Typer


class Context(NamedTuple):
    logdir: Path
    verbose: bool
    enc_path: Path


app = FCTyperApp("fc-kubernetes")
context: Context


@app.callback(no_args_is_help=True)
def fc_kubernetes(
    verbose: bool = Option(
        False,
        "--verbose",
        "-v",
        help="Show debug messages and code locations.",
    ),
    logdir: Path = Option(
        exists=True,
        writable=True,
        file_okay=False,
        default="/var/log",
        help="Directory for log files, expects a fc-agent subdirectory there.",
    ),
    enc_path: Path = Option(
        dir_okay=False,
        default="/etc/nixos/enc.json",
        help="Path to enc.json",
    ),
):
    global context

    context = Context(
        logdir=logdir,
        verbose=verbose,
        enc_path=enc_path,
    )

    init_logging(verbose, logdir, syslog_identifier="fc-kubernetes")


@app.command(
    help="Drain this node and wait for completion",
)
def drain(
    timeout: int = Option(
        default=300, help="Timeout in seconds passed to kubectl drain."
    ),
    reason: str = Option(
        default="fc-kubernetes-drain",
        help=(
            "Set a node label before draining. Labels can only contain "
            "alphanumeric characters and '-', '_' or '.', and must start and "
            "end with an alphanumeric character."
        ),
    ),
    strict_state_check: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    try:
        fc.util.kubernetes.drain(
            log, hostname, timeout, reason, strict_state_check
        )
    except fc.util.kubernetes.NodeDrainTimeout:
        raise Exit(EXIT_TEMPFAIL)


@app.command()
def ready(
    strict_state_check: Optional[bool] = False,
    label_must_match: Optional[str] = Option(
        default=None,
        help="Only set nodes to ready which match a given label.",
    ),
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.kubernetes.uncordon(
        log, hostname, strict_state_check, label_must_match
    )


all_nodes_app = Typer(
    pretty_exceptions_show_locals=False,
    help="Commands that affect all nodes in the cluster",
    no_args_is_help=True,
)
app.add_typer(all_nodes_app, name="all-nodes")


@all_nodes_app.command(
    name="ready",
    help="Mark nodes as ready",
)
def ready_all(
    strict_state_check: Optional[bool] = False,
    label_must_match: Optional[str] = Option(
        default=None,
        help="Only set nodes to ready which match a given label.",
    ),
    skip_nodes_in_maintenance: Optional[bool] = Option(
        default=True,
        help="Check maintenance state of nodes and skip when not in service.",
    ),
):
    log = structlog.get_logger()
    node_names = fc.util.kubernetes.get_all_agent_node_names()
    with directory_connection(context.enc_path) as directory:
        for node_name in node_names:
            fc.util.kubernetes.uncordon(
                log,
                node_name,
                strict_state_check,
                label_must_match,
                skip_nodes_in_maintenance,
                directory,
            )


if __name__ == "__main__":
    app()
