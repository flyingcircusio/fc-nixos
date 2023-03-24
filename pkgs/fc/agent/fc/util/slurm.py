import socket
import subprocess
import time
from collections import Counter
from enum import Enum
from functools import reduce
from typing import NamedTuple, Optional

import pyslurm
from fc.util.checks import CheckResult
from fc.util.directory import directory_connection, is_node_in_service


class NodeStateError(Exception):
    def __init__(self, state: str, flags: list[str]):
        self.state = state
        self.flags = flags


class NodeStateTimeout(Exception):
    def __init__(self, remaining_node_states: dict[str, str]):
        self.remaining_node_states = remaining_node_states


class DrainingAction(Enum):
    NO_OP = 0
    DRAIN = 1
    WAIT = 2


class DrainPreCheckResult(NamedTuple):
    state: str
    flags: list[str]
    draining_action: DrainingAction


def get_node_info(node_name):
    return pyslurm.node().get_node(node_name)[node_name]


def is_node_in_error(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "ERROR"


def is_node_state_mixed(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "MIXED"


def is_node_failed(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "FAILED"


def is_node_idle(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "IDLE"


def is_node_down(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "DOWN"


def is_node_draining(node_info):
    state, *flags = node_info["state"].split("+")
    return "DRAIN" in flags


def is_node_completing(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "COMPLETING"


def is_node_allocated(node_info):
    state, *flags = node_info["state"].split("+")
    return state == "ALLOCATED"


def is_node_drained(log, node_info):
    state, *flags = node_info["state"].split("+")
    drained = state in ("IDLE", "IDLE*", "DOWN", "DOWN*") and "DRAIN" in flags
    log.debug(
        "is-node-drained",
        drained=drained,
        node=node_info["name"],
        state=state,
        flags=flags,
    )
    return drained


def get_all_node_names():
    return pyslurm.node().get().keys()


def update_nodes(state_change: dict):
    return pyslurm.node().update(state_change)


def run_drain_pre_checks(log, node_name, strict_state_check):
    log = log.bind(node=node_name)

    node_info = get_node_info(node_name)
    state, *flags = node_info["state"].split("+")

    if is_node_drained(log.bind(op="pre-check"), node_info):
        if strict_state_check:
            log.error("drain-pre-check-state-error", state=state, flags=flags)
            raise NodeStateError(state, flags)
        else:
            log.info(
                "drain-pre-already-drained",
                _replace_msg="{node} is already drained",
            )
            return DrainPreCheckResult(state, flags, DrainingAction.NO_OP)

    if "DRAIN" in flags:
        if strict_state_check:
            log.error("drain-state-error", state=state, flags=flags)
            raise NodeStateError(state, flags)
        else:
            log.info(
                "drain-pre-already-draining",
                _replace_msg=(
                    "{node} already started draining. Will wait until the node "
                    " is drained."
                ),
            )
            return DrainPreCheckResult(state, flags, DrainingAction.WAIT)

    if "*" in state:
        log.warn(
            "drain-pre-unresponsive",
            _replace_msg=(
                "{node} does need draining in state {state} and does not "
                "respond at the moment. Will still try to drain the node."
            ),
            state=state,
            flags=flags,
        )
    else:
        log.info(
            "drain-pre-needs-draining",
            _replace_msg="{node} is in state {state} and needs draining.",
            state=state,
            flags=flags,
        )

    return DrainPreCheckResult(state, flags, DrainingAction.DRAIN)


def drain(
    log,
    node_name,
    timeout: int,
    reason: str,
    strict_state_check: bool = False,
):
    log.debug(
        "drain-start",
        timeout=timeout,
        reason=reason,
        node=node_name,
        strict_state_check=strict_state_check,
    )

    check_result = run_drain_pre_checks(log, node_name, strict_state_check)

    match check_result.draining_action:
        case DrainingAction.NO_OP:
            return
        case DrainingAction.WAIT:
            pass
        case DrainingAction.DRAIN:
            state_change_drain = {
                "node_names": node_name,
                "node_state": pyslurm.NODE_STATE_DRAIN,
                "reason": reason,
            }
            result = update_nodes(state_change_drain)
            log.debug("node-update-result", result=result)

    start_time = time.time()
    elapsed = 0.0
    ii = 0

    while elapsed < timeout:
        node_info = get_node_info(node_name)

        drain_log = log.bind(
            op="drain-wait", elapsed=int(elapsed), timeout=timeout
        )
        if is_node_drained(drain_log, node_info):
            log.info(
                "drain-finished",
                elapsed=int(elapsed),
                node=node_name,
                state=node_info["state"],
            )
            return

        pause = min([15, 2**ii])
        log.debug("drain-wait", sleep=pause)
        time.sleep(pause)
        ii += 1
        elapsed = time.time() - start_time

    state_str = get_node_info(node_name)["state"]
    state, *flags = state_str.split("+")
    log.error(
        "drain-timeout",
        _replace_msg=(
            "{node} did not finish draining in time, waited {timeout} "
            "seconds. State is '{state}' with flags {flags}."
        ),
        flags=flags,
        state=state,
        timeout=timeout,
    )
    raise NodeStateTimeout({node_name: state_str})


def drain_many(
    log,
    node_names,
    timeout: int,
    reason: str,
    strict_state_check: bool = False,
):
    log.debug("drain-many-start", nodes=node_names)

    nodes_to_drain = set()
    nodes_to_wait_for = set()

    for node_name in node_names:
        check_result = run_drain_pre_checks(log, node_name, strict_state_check)

        match check_result.draining_action:
            case DrainingAction.NO_OP:
                pass
            case DrainingAction.WAIT:
                nodes_to_wait_for.add(node_name)
            case DrainingAction.DRAIN:
                nodes_to_drain.add(node_name)
                nodes_to_wait_for.add(node_name)

    if not nodes_to_wait_for:
        log.info(
            "drain-many-nothing-to-do",
            _replace_msg="OK: All nodes are already drained.",
        )
        return

    if nodes_to_drain:
        state_change_drain = {
            "node_names": ",".join(nodes_to_drain),
            "node_state": pyslurm.NODE_STATE_DRAIN,
            "reason": reason,
        }
        result = update_nodes(state_change_drain)
        log.debug("node-update-result", result=result)

    log.info(
        "drain-many-waiting",
        num_waiting_nodes=len(nodes_to_wait_for),
        _replace_msg="Waiting for {num_waiting_nodes} nodes to drain.",
    )

    start_time = time.time()
    elapsed = 0.0
    ii = 0

    while elapsed < timeout:
        drained_nodes = set()
        for node_name in nodes_to_wait_for:
            node_info = get_node_info(node_name)

            drain_log = log.bind(
                op="drain-wait", elapsed=int(elapsed), timeout=timeout
            )

            if is_node_drained(drain_log, node_info):
                log.info(
                    "node-drained",
                    _replace_msg="{node} is now fully drained.",
                    node=node_name,
                )

                drained_nodes.add(node_name)

        for node_name in drained_nodes:
            nodes_to_wait_for.remove(node_name)

        if not nodes_to_wait_for:
            log.info(
                "drain-many-finished",
                _replace_msg="All nodes are drained after {elapsed} seconds.",
                elapsed=int(elapsed),
            )
            return

        log.debug(
            "drain-all-wait",
            elapsed=int(elapsed),
            timeout=timeout,
            num_waiting_nodes=len(nodes_to_wait_for),
        )

        pause = min([15, 2**ii])
        log.debug("drain-wait", sleep=pause)
        time.sleep(pause)
        ii += 1
        elapsed = time.time() - start_time

    # Loop finished => time limit reached

    remaining_node_states = {
        o: get_node_info(o)["state"] for o in nodes_to_wait_for
    }

    log.error(
        "drain-many-timeout",
        timeout=timeout,
        remaining_node_states=remaining_node_states,
        num_remaining=len(nodes_to_wait_for),
        _replace_msg=(
            "{num_remaining} node(s) did not drain in time, waited "
            "{timeout} seconds for: {remaining_node_states}"
        ),
    )
    raise NodeStateTimeout(remaining_node_states)


def down(log, node_name, reason: str, strict_state_check: bool = False):
    log = log.bind(node=node_name)
    log.debug("down-start")

    node_info = get_node_info(node_name)
    state, *flags = node_info["state"].split("+")
    log.debug("down-state-pre", state=state, flags=flags)

    if state in ("DOWN", "DOWN*"):
        if strict_state_check:
            log.error("down-state-error", state=state, flags=flags)
            raise NodeStateError(state, flags)
        else:
            log.info(
                "down-already-reached",
                _replace_msg="{node} is already in {state} state.",
                state=state,
            )
            return

    state_change_down = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_STATE_DOWN,
        "reason": reason,
    }
    result = update_nodes(state_change_down)
    log.debug("node-update-result", result=result)
    log.info(
        "down-finished",
        _replace_msg="{node} is set to DOWN.",
    )


class ReadyPreCheckResult(NamedTuple):
    state: str
    flags: list[str]
    action: bool


def run_ready_pre_checks(
    log,
    node_name,
    strict_state_check,
    reason_must_match,
    skip_in_maintenance,
    directory,
):
    log = log.bind(node=node_name)
    node_info = get_node_info(node_name)
    state, *flags = node_info["state"].split("+")
    log.debug("ready-pre-node-state", state=state, flags=flags)

    if state in ("ALLOCATED", "IDLE", "MIXED") and "DRAIN" not in flags:
        if strict_state_check:
            log.error("ready-state-error", state=state, flags=flags)
            raise NodeStateError(state, flags)
        else:
            log.info(
                "ready-already-reached",
                _replace_msg=(
                    "{node} is already in a ready state ({state}). No change."
                ),
                state=state,
            )
            return ReadyPreCheckResult(state, flags, action=False)

    if state in ("ALLOCATED*", "IDLE*", "MIXED*") and "DRAIN" not in flags:
        if strict_state_check:
            log.error("ready-state-error", state=state, flags=flags)
            raise NodeStateError(state, flags)
        else:
            log.warn(
                "ready-already-reached-unresponsive",
                _replace_msg=(
                    "{node} is already in a ready state ({state}) but not "
                    "responding at the moment. No change."
                ),
                state=state,
            )
            return ReadyPreCheckResult(state, flags, action=False)

    if reason_must_match and reason_must_match not in node_info["reason"]:
        log.info(
            "ready-pre-reason-not-matched",
            _replace_msg=(
                "{node} cannot be set to ready because the reason '{reason}' "
                "does not contain the expected string '{expected}'"
            ),
            expected=reason_must_match,
            reason=node_info["reason"],
        )
        return ReadyPreCheckResult(state, flags, action=False)

    if skip_in_maintenance and not is_node_in_service(directory, node_name):
        log.info(
            "ready-pre-not-in-service",
            node=node_name,
            _replace_msg="{node} is still in maintenance, skipping.",
        )
        return ReadyPreCheckResult(state, flags, action=False)

    if "*" in state:
        log.warn(
            "ready-pre-doit-unresponsive",
            _replace_msg=(
                "{node} is in state {state} and does not respond at the "
                "moment but can still be set to ready."
            ),
            state=state,
            flags=flags,
        )
    else:
        log.info(
            "ready-pre-doit",
            _replace_msg="{node} is in state {state} and can be set to ready.",
            state=state,
            flags=flags,
        )
    return ReadyPreCheckResult(state, flags, action=True)


def ready(
    log,
    node_name,
    strict_state_check: bool = False,
    reason_must_match: Optional[str] = None,
    skip_in_maintenance=False,
    directory=None,
):
    log = log.bind(node=node_name)
    log.debug("ready-start")

    result = run_ready_pre_checks(
        log,
        node_name,
        strict_state_check,
        reason_must_match,
        skip_in_maintenance,
        directory,
    )

    if not result.action:
        return

    state_change_ready = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_RESUME,
    }
    result = update_nodes(state_change_ready)
    log.debug("node-update-result", result=result)

    log.info(
        "ready-finished",
        _replace_msg="{node} set to ready.",
    )


def check_controller(log, hostname):
    errors = []
    warnings = []

    try:
        pyslurm.slurm_ping(0)
    except ValueError as e:
        log.error("slurm-controller-ping-failed", exc_info=True)
        errors.append(f"Failed - {e.args[0]}")

    all_nodes_info = pyslurm.node().get().items()

    if not all_nodes_info:
        errors.append("No nodes configured")
        return CheckResult(errors)

    nodes_out = {}
    nodes_in = {}
    nodes_offline = {}
    nodes_unexpected = {}

    num_nodes = len(all_nodes_info)

    for name, info in all_nodes_info:
        state_parts = info["state"].split("+")
        match state_parts:
            case [
                ("IDLE*" | "DOWN*" | "ALLOCATED*" | "MIXED*" | "COMPLETING*"),
                *_,
            ]:
                nodes_offline[name] = info
            case [("DOWN"), *_]:
                nodes_out[name] = info
            case [("ALLOCATED" | "IDLE" | "COMPLETING" | "MIXED"), *flags]:
                if "DRAIN" in flags:
                    nodes_out[name] = info
                else:
                    nodes_in[name] = info
            case unexpected:
                nodes_unexpected[name] = info
                log.warn("check-unexpected-node-state", state=unexpected)

    if nodes_unexpected:
        nodes_with_state = [
            f"{n} ({o['state']})" for n, o in nodes_unexpected.items()
        ]
        node_state_str = ", ".join(nodes_with_state)
        warnings.append(
            f"{len(nodes_unexpected)}/{num_nodes} nodes are in an unexpected "
            f"state: " + node_state_str
        )

    if not nodes_in:
        nodes_with_state = [
            f"{n} ({o['state']}, \"{o['reason']}\")"
            for n, o in nodes_out.items()
        ] + [f"{n} (not responding)" for n in nodes_offline]

        node_state_str = ", ".join(nodes_with_state)
        errors.append(f"All nodes cannot accept jobs: {node_state_str}.")

    elif nodes_out or nodes_offline:
        nodes_with_state = [
            f"{n} ({o['state']}, \"{o['reason']}\")"
            for n, o in nodes_out.items()
        ] + [f"{n} (not responding)" for n in nodes_offline]

        node_state_str = ", ".join(nodes_with_state)
        num_offline_out = len(nodes_offline) + len(nodes_out)
        warnings.append(
            f"{num_offline_out}/{num_nodes} nodes cannot accept jobs: "
            + node_state_str
            + "."
        )

    stats = pyslurm.statistics().get()

    info = [
        f"All {num_nodes} nodes are operational.",
        f"Running jobs: {stats['jobs_running']}.",
        f"Pending jobs: {stats['jobs_pending']}.",
        f"Total started jobs: {stats['jobs_started']}.",
        f"Slurm version:" f" {pyslurm.version()}",
    ]

    return CheckResult(errors, warnings, info)


def check_node(log, hostname):
    errors = []
    warnings = []
    info = []

    slurmd_active_proc = subprocess.run(
        ["systemctl", "is-active", "--quiet", "slurmd"]
    )
    if slurmd_active_proc.returncode > 0:
        errors.append("slurm daemon is inactive, no jobs will be run.")

    munged_active_proc = subprocess.run(
        ["systemctl", "is-active", "--quiet", "munged"]
    )
    if munged_active_proc.returncode > 0:
        errors.append(
            "munge daemon is inactive, no slurm API interaction possible."
        )
        return CheckResult(errors)

    try:
        node_info = get_node_info(hostname)
    except Exception as e:
        log.error("check-node-api-error", exc_info=True)
        errors.append("Cannot get node info from API: {e}")
        return CheckResult(errors)

    state, *flags = node_info["state"].split("+")

    if state == "DOWN":
        warnings.append("Node is marked as DOWN, no jobs will be run.")
    elif "DRAIN" in flags:
        warnings.append("Node is draining, no new jobs will be accepted.")
    else:
        info = [f"Node state is {state}."]

    return CheckResult(errors, warnings, info)


def check(log, hostname) -> CheckResult:
    results = []

    try:
        controller_names = pyslurm.get_controllers()
    except ValueError as e:
        return CheckResult(errors=[e.args[0]], warnings=[])

    if hostname in controller_names:
        results.append(check_controller(log, hostname))

    if hostname in pyslurm.node().get():
        results.append(check_node(log, hostname))

    return reduce(CheckResult.merge, results)


def get_account_metrics(account, running, pending, suspended) -> dict:
    return {
        "name": "slurm_account",
        "account": account,
        "cpus_running": sum(j["num_cpus"] for j in running),
        "jobs_running": len(running),
        "jobs_pending": len(pending),
        "jobs_suspended": len(suspended),
    }


def get_accounts_metrics(log, jobs) -> list[dict]:
    running_per_acc = {}
    pending_per_acc = {}
    suspended_per_acc = {}

    for job in jobs:
        acc = job["account"]
        match job["job_state"]:
            case "RUNNING":
                running_for_acc = running_per_acc.setdefault(acc, [])
                running_for_acc.append(job)
            case "PENDING":
                pending_for_acc = pending_per_acc.setdefault(acc, [])
                pending_for_acc.append(job)
            case "SUSPENDED":
                suspended_for_acc = suspended_per_acc.setdefault(acc, [])
                suspended_for_acc.append(job)
            case "COMPLETED" | "CANCELLED":
                pass
            case other:
                log.warn("slurm-metrics-unknown-job-state", state=other)

    accounts_metrics = []

    for account in (
        running_per_acc.keys()
        | pending_per_acc.keys()
        | suspended_per_acc.keys()
    ):
        running = running_per_acc.get(acc, [])
        pending = pending_per_acc.get(acc, [])
        suspended = suspended_per_acc.get(acc, [])

        accounts_metrics.append(
            get_account_metrics(account, running, pending, suspended)
        )

    return accounts_metrics


def get_cpu_metrics(nodes) -> dict:
    return {
        "name": "slurm_cpus",
        "total": sum(o["cpus"] for o in nodes),
        "alloc": sum(o["alloc_cpus"] for o in nodes),
    }


def get_node_metrics(nodes) -> dict:
    return {
        "name": "slurm_nodes",
        "total": len(nodes),
        "idle": len([1 for o in nodes if is_node_idle(o)]),
        "alloc": len([1 for o in nodes if is_node_allocated(o)]),
        "comp": len([1 for o in nodes if is_node_completing(o)]),
        "down": len([1 for o in nodes if is_node_down(o)]),
        "drain": len([1 for o in nodes if is_node_draining(o)]),
        "err": len([1 for o in nodes if is_node_in_error(o)]),
        "fail": len([1 for o in nodes if is_node_failed(o)]),
        "mix": len([1 for o in nodes if is_node_state_mixed(o)]),
    }


def get_queue_metrics(jobs) -> dict:
    state_counter = Counter(j["job_state"].lower() for j in jobs)
    return {"name": "slurm_queue", **state_counter}


def get_scheduler_metrics(stats) -> dict:
    sched_count = stats["schedule_cycle_counter"]
    bf_count = stats["bf_cycle_counter"]
    mean_cycle = (
        stats["schedule_cycle_sum"] / sched_count if sched_count > 0 else 0
    )
    backfill_mean_cycle = (
        stats["bf_cycle_sum"] / bf_count if bf_count > 0 else 0
    )
    backfill_depth_mean = (
        stats["bf_depth_sum"] / bf_count if bf_count > 0 else 0
    )

    return {
        "name": "slurm_scheduler",
        "threads": stats["server_thread_count"],
        "queue_size": stats["schedule_queue_len"],
        "last_cycle": stats["schedule_cycle_last"],
        "mean_cycle": mean_cycle,
        "backfill_last_cycle": stats["bf_cycle_last"],
        "backfill_mean_cycle": backfill_mean_cycle,
        "backfill_depth_mean": backfill_depth_mean,
        "backfilled_jobs_since_start_total": stats["bf_backfilled_jobs"],
        "backfilled_jobs_since_cycle_total": stats["bf_last_backfilled_jobs"],
    }


def get_metrics(log) -> list[dict]:
    stats = pyslurm.statistics().get()
    nodes = pyslurm.node().get().values()
    jobs = pyslurm.job().get().values()

    return [
        *get_accounts_metrics(log, jobs),
        get_cpu_metrics(nodes),
        get_node_metrics(nodes),
        get_queue_metrics(jobs),
        get_scheduler_metrics(stats),
    ]
