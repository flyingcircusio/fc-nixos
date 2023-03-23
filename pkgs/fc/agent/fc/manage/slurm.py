import json
import os
import socket
import traceback
from pathlib import Path
from typing import NamedTuple, Optional

import fc.util.slurm
import rich
import rich.syntax
import structlog
from fc.util.directory import directory_connection
from fc.util.logging import init_logging
from typer import Exit, Option, Typer


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
        default="executed fc-slurm drain", help="reason for draining the node"
    ),
    strict_state_check: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.drain(log, hostname, timeout, reason, strict_state_check)


@app.command(
    help="Drain, wait for completion and down this node",
)
def drain_and_down(
    timeout: int = Option(
        default=300, help="Wait for seconds for every job to finish."
    ),
    reason: str = Option(
        default="executed fc-slurm drain-and-down",
        help="reason for draining and downing the node",
    ),
    strict_state_check: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.drain(log, hostname, timeout, reason, strict_state_check)
    fc.util.slurm.down(log, hostname, reason, strict_state_check)


@app.command()
def down(
    strict_state_check: Optional[bool] = False,
    reason: str = Option(
        default="executed fc-slurm down",
        help="reason for draining the nodes",
    ),
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.down(log, hostname, reason, strict_state_check)


@app.command()
def ready(
    strict_state_check: Optional[bool] = False,
):
    log = structlog.get_logger()
    hostname = socket.gethostname()
    fc.util.slurm.ready(log, hostname, strict_state_check)


@app.command(help="Checks state of this machine")
def check():
    log = structlog.get_logger()
    hostname = socket.gethostname()
    try:
        result = fc.util.slurm.check(log, hostname)
    except Exception:
        print("UNKNOWN: Exception occurred while running checks")
        traceback.print_exc()
        raise Exit(3)

    print(result.format_output())
    if result.exit_code:
        raise Exit(result.exit_code)


@app.command(help="Produces metrics for telegraf's JSON input")
def metrics():
    log = structlog.get_logger()
    jso = json.dumps(fc.util.slurm.get_metrics(log))
    print(jso)


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
        default="executed fc-slurm all-nodes drain-and-down",
        help="reason for draining the nodes",
    ),
    strict_state_check: Optional[bool] = False,
):
    log = structlog.get_logger()
    # This drains all nodes in parallel.
    log.info("drain-all", _replace_msg="Draining all nodes in the cluster.")
    fc.util.slurm.drain_many(
        log,
        fc.util.slurm.get_all_node_names(),
        timeout,
        reason,
        strict_state_check,
    )
    # Setting the state is fast, we can do it sequentially.
    log.info("down-all", _replace_msg="Setting all nodes to down.")
    for node_name in fc.util.slurm.get_all_node_names():
        fc.util.slurm.down(log, node_name, reason, strict_state_check)


@all_nodes_app.command(
    name="ready",
    help="Mark nodes as ready",
)
def ready_all(
    required_in_service: list[str] = Option(
        default=[],
        help=(
            "Machine that should also be checked for its maintenance state."
            "If any of the given machines are still in maintenance, no node "
            "will be set to ready."
        ),
    ),
    strict_state_check: Optional[bool] = False,
    reason_must_match: Optional[str] = Option(
        default=None,
        help="Only set nodes to ready which match a given reason string.",
    ),
    skip_nodes_in_maintenance: Optional[bool] = Option(
        default=True,
        help="Check maintenance state of nodes and skip when not in service.",
    ),
):
    log = structlog.get_logger()
    node_names = fc.util.slurm.get_all_node_names()
    if required_in_service:
        # We have to check maintenance (or in-service) state against the
        # directory for some machines before we can start action.
        with directory_connection(context.enc_path) as directory:
            # Stop action when any required machine is not in-service
            required_machines_not_in_service = []
            for machine in required_in_service:
                log.debug("ready-all-check-required-machine", machine=machine)
                if not fc.util.directory.is_node_in_service(directory, machine):
                    required_machines_not_in_service.append(machine)

            if required_machines_not_in_service:
                log.info(
                    "ready-all-required-machines-not-in-service",
                    _replace_msg=(
                        "Cannot set nodes to ready. "
                        "Required machines not in service: "
                        "{not_in_service}"
                    ),
                    not_in_service=required_machines_not_in_service,
                )
                return

    with directory_connection(context.enc_path) as directory:
        for node_name in node_names:
            fc.util.slurm.ready(
                log,
                node_name,
                strict_state_check,
                reason_must_match,
                skip_nodes_in_maintenance,
                directory,
            )


@all_nodes_app.command()
def state(as_json: bool = True):
    node_names = fc.util.slurm.get_all_node_names()
    node_info = [fc.util.slurm.get_node_info(name) for name in node_names]
    if as_json:
        output = json.dumps(node_info, indent=2)
    else:
        output = node_info
    rich.print(output)
