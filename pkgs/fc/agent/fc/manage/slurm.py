import json
import os
import rich
import socket
import structlog
from pathlib import Path
from typer import Option, Typer
from typing import NamedTuple, Optional

from fc.util.directory import directory_connection
import fc.util.slurm
from fc.util.logging import init_logging


class Context(NamedTuple):
    logdir: Path
    verbose: bool
    enc_path: Path


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
        default="/var/log",
        help="Directory for log files, expects a fc-agent subdirectory there.",
    ),
    enc_path: Path = Option(
        dir_okay=False,
        # We don't need enc_path for every command.
        # XXX: should we move commands that don't need sudo somewhere else?
        readable=False,
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

    # Use logdir if it's writable for the current user.
    logdir_to_use = logdir if os.access(logdir, os.W_OK) else None
    init_logging(verbose, logdir_to_use, syslog_identifier="fc-slurm")


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


@app.command(help="Just displays current node state at the moment.")
def check():
    log = structlog.get_logger()
    hostname = socket.gethostname()
    node_info = fc.util.slurm.get_node_info(hostname)
    rich.print(node_info)


all_nodes_app = Typer(
    pretty_exceptions_show_locals=False,
    help="Commands that affect all nodes in the cluster",
    no_args_is_help=True,
)
app.add_typer(all_nodes_app, name="all-nodes")


@all_nodes_app.command(help="Drain and down all nodes", name="drain-and-down")
def drain_and_down_all(
    timeout: int = Option(
        default=300, help="Wait for seconds for every job to finish."
    ),
    reason: str = Option(
        default="fc-slurm all-nodes", help="reason for draining the nodes"
    ),
    nothing_to_do_is_ok: Optional[bool] = False,
):
    log = structlog.get_logger()
    # This drains all nodes in parallel.
    fc.util.slurm.drain_many(
        log,
        fc.util.slurm.get_all_node_names(),
        timeout,
        reason,
        nothing_to_do_is_ok,
    )
    # Setting the state is fast, we can do it sequentially.
    for node_name in fc.util.slurm.get_all_node_names():
        fc.util.slurm.down(log, node_name, nothing_to_do_is_ok, reason)


def is_node_in_service(directory, node) -> bool:
    return directory.lookup_node(node)["parameters"]["servicing"]


@all_nodes_app.command(
    name="ready",
    help="Mark all nodes as ready",
)
def ready_all(
    nothing_to_do_is_ok: Optional[bool] = False,
    skip_nodes_in_maintenance: Optional[bool] = True,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    node_names = fc.util.slurm.get_all_node_names()

    if skip_nodes_in_maintenance:
        node_names_to_mark_ready = []

        with directory_connection(context.enc_path) as directory:
            for node in node_names:
                if node == hostname or is_node_in_service(directory, node):
                    node_names_to_mark_ready.append(node)
                else:
                    log.info(
                        "ready-all-node-not-in-service",
                        node=node,
                        _replace_msg=(
                            "Node {node} is still in maintenance, skipping."
                        ),
                    )

    else:
        node_names_to_mark_ready = node_names

    for node_name in node_names_to_mark_ready:
        fc.util.slurm.ready(log, node_name, nothing_to_do_is_ok)


@all_nodes_app.command()
def state(as_json: bool = True):
    node_names = fc.util.slurm.get_all_node_names()
    node_info = [fc.util.slurm.get_node_info(name) for name in node_names]
    if as_json:
        output = json.dumps(node_info, indent=2)
    else:
        output = node_info
    rich.print(output)
