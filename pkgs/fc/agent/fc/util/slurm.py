from collections import Counter
from functools import reduce
from typing import NamedTuple

import time

import pyslurm
from fc.util.checks import CheckResult

NODE_API = pyslurm.node()

DOWN_STATES = {"DOWN", "POWERED_DOWN", "DOWN+DRAIN"}

DOWN_STATES_SPLIT = {"DOWN", "POWERED_DOWN"}

DRAIN_STATES = {"IDLE+DRAIN", "DRAINING", "DOWN+DRAIN"}

DRAIN_STATES_SPLIT = {"DRAIN", "DRAINING"}


class NodeStateError(Exception):
    def __init__(self, state):
        self.state = state


class NodeStateTimeout(Exception):
    def __init__(self, state):
        self.state = state


def get_node_info(node_name):
    return NODE_API.get_node(node_name)[node_name]


def is_node_in_error(node_info):
    state_parts = node_info["state"].split("+")
    return "ERROR" in state_parts


def is_node_state_mixed(node_info):
    state_parts = node_info["state"].split("+")
    return "MIXED" in state_parts


def is_node_failed(node_info):
    state_parts = node_info["state"].split("+")
    return "FAILED" in state_parts


def is_node_idle(node_info):
    state_parts = node_info["state"].split("+")
    return "IDLE" in state_parts


def is_node_down(node_info):
    state_parts = node_info["state"].split("+")
    return any(s for s in state_parts if s in DOWN_STATES_SPLIT)


def is_node_drain(node_info):
    state_parts = node_info["state"].split("+")
    return any(s for s in state_parts if s in DRAIN_STATES_SPLIT)


def is_node_completing(node_info):
    state_parts = node_info["state"].split("+")
    return "COMPLETING" in state_parts


def is_node_allocated(node_info):
    state_parts = node_info["state"].split("+")
    return "ALLOCATED" in state_parts


def get_all_node_names():
    return NODE_API.get().keys()


class DrainPreCheckResult(NamedTuple):
    needs_draining: bool


def run_drain_pre_checks(log, node_name, nothing_to_do_is_ok):
    log = log.bind(node=node_name)

    node_info = get_node_info(node_name)
    node_state = node_info["state"]
    if "DRAIN" in node_state:
        if nothing_to_do_is_ok:
            log.info(
                "drain-already-reached",
                _replace_msg="Node {node} is already in a draining state",
            )
            return DrainPreCheckResult(needs_draining=False)
        else:
            log.error("drain-state-error", state=node_state)
            raise NodeStateError(node_state)

    if node_state == "DOWN":
        if nothing_to_do_is_ok:
            log.info(
                "drain-already-down",
                _replace_msg="Node {node} is already down",
            )
            return DrainPreCheckResult(needs_draining=False)
        else:
            log.error("drain-state-error", state=node_state)
            raise NodeStateError(node_state)

    return DrainPreCheckResult(needs_draining=True)


def drain(
    log,
    node_name,
    timeout: int,
    reason: str,
    nothing_to_do_is_ok: bool,
):
    log.info("drain-start")

    check_result = run_drain_pre_checks(log, node_name, nothing_to_do_is_ok)
    if not check_result.needs_draining:
        return

    state_change_drain = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_STATE_DRAIN,
        "reason": reason,
    }
    result = NODE_API.update(state_change_drain)
    log.debug("node-update-result", result=result)

    for ii in range(timeout):
        node_state = get_node_info(node_name)["state"]
        if node_state in ("IDLE+DRAIN", "DOWN+DRAIN"):
            log.info("drain-finished", result=result)
            return

        log.debug(
            "drain-wait", waiting_for=ii, timeout=timeout, state=node_state
        )
        time.sleep(1)

    log.error(
        "drain-timeout",
        timeout=timeout,
        _replace=(
            "Node {node} did not reach IDLE+DRAIN state in time, "
            "waited for {timeout} seconds)"
        ),
    )
    raise NodeStateTimeout(node_state)


def drain_many(
    log,
    node_names,
    timeout: int,
    reason: str,
    nothing_to_do_is_ok: bool,
):
    log.info("drain-all-start", nodes=node_names)

    waiting_nodes = set()

    for node_name in node_names:
        check_result = run_drain_pre_checks(log, node_name, nothing_to_do_is_ok)
        if check_result.needs_draining:
            waiting_nodes.add(node_name)

    if not waiting_nodes:
        log.info(
            "drain-many-nothing-to-do",
            _replace_msg="OK: All nodes are already in a draining state.",
        )
        return

    state_change_drain = {
        "node_names": ",".join(node_names),
        "node_state": pyslurm.NODE_STATE_DRAIN,
        "reason": reason,
    }
    result = NODE_API.update(state_change_drain)
    log.debug("node-update-result", result=result)

    for ii in range(timeout):

        for node_name in set(waiting_nodes):
            node_state = get_node_info(node_name)["state"]
            if node_state == "IDLE+DRAIN":
                log.info(
                    "drain-node-finished",
                    node=node_name,
                    result=result,
                    time=ii,
                )

                waiting_nodes.remove(node_name)

                if not waiting_nodes:
                    log.info("drain-all-finished", result=result, time=ii)
                    return

            log.debug(
                "drain-all-wait",
                waiting_for=ii,
                timeout=timeout,
                state=node_state,
            )

        time.sleep(1)

    log.error(
        "drain-timeout",
        timeout=timeout,
        waiting_nodes=waiting_nodes,
        _replace=(
            "Nodes {waiting_nodes} did not reach IDLE+DRAIN state in time, "
            "waited for {timeout} seconds)"
        ),
    )
    raise NodeStateTimeout(node_state)


def down(log, node_name, nothing_to_do_is_ok: bool, reason: str):
    log = log.bind(node=node_name)
    log.info("down-start")

    node_info = get_node_info(node_name)
    node_state = node_info["state"]

    if node_state in DOWN_STATES:
        if nothing_to_do_is_ok:
            log.info(
                "down-already-reached",
                _replace_msg="Node {node} is already in a DOWN state",
            )
            return
        else:
            log.error("down-error", state=node_state)
            raise NodeStateError(node_state)

    state_change_down = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_STATE_DOWN,
        "reason": reason,
    }
    result = NODE_API.update(state_change_down)
    log.debug("node-update-result", result=result)
    log.info(
        "down-finished",
        _replace_msg="Node {node} is now marked as DOWN now.",
    )


def ready(
    log,
    node_name,
    nothing_to_do_is_ok: bool,
):
    log = log.bind(node=node_name)
    log.info("ready-start")

    node_info = get_node_info(node_name)
    node_state = node_info["state"]

    if node_state in ("IDLE", "ALLOCATED", "POWERING_UP"):
        if nothing_to_do_is_ok:
            log.info(
                "ready-already-reached",
                _replace_msg="Node {node} is already in a ready state.",
            )
            return
        else:
            log.error("ready-error", state=node_state)
            raise NodeStateError(node_state)

    state_change_ready = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_RESUME,
    }
    result = NODE_API.update(state_change_ready)
    log.debug("node-update-result", result=result)
    log.info(
        "ready-finished",
        _replace_msg="Node {node} has resumed operations",
    )


def check_controller(log, hostname):
    errors = []
    warnings = []

    try:
        pyslurm.slurm_ping(0)
    except ValueError as e:
        log.error("slurm-controller-ping-failed", exc_info=True)
        errors.append(f"Failed - {e.args[0]}")
    except ValueError as e:
        log.error("slurm-controller-ping-failed", exc_info=True)
        errors.append(f"Failed - {e.args[0]}")

    node_info = NODE_API.get().items()

    nodes_out = {}
    nodes_in = {}
    nodes_unexpected = {}

    num_nodes = len(node_info)

    for name, info in node_info:
        state_parts = info["state"].split("+")
        match state_parts:
            case ["DOWN", *_]:
                nodes_out[name] = info
            case [("ALLOC" | "IDLE" | "COMPLETING" | "MIXED"), *flags]:
                if "DRAIN" in flags:
                    nodes_out[name] = info
                else:
                    nodes_in[name] = info
            case unexpected:
                nodes_unexpected[name] = info
                log.warn("check-unexpected-node-state", state=unexpected)

    if nodes_unexpected:
        nodes_with_state = [f"{n} ({o['state']})" for n, o in nodes_out.items()]
        node_state_str = ", ".join(nodes_with_state)
        warnings.append(
            f"{len(nodes_out)}/{num_nodes} nodes are in an unexpected state: "
            + node_state_str
        )

    if not (nodes_out or nodes_in):
        errors.append("No nodes configured")
    elif not nodes_in:
        nodes_with_state = [f"{n} ({o['state']})" for n, o in nodes_out.items()]
        node_state_str = ", ".join(nodes_with_state)
        errors.append(f"All nodes cannot accept jobs: {node_state_str}")
    elif nodes_out:
        nodes_with_state = [f"{n} ({o['state']})" for n, o in nodes_out.items()]
        node_state_str = ", ".join(nodes_with_state)
        warnings.append(
            f"{len(nodes_out)}/{num_nodes} nodes cannot accept jobs: "
            + node_state_str
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
    """
    XXX: unclear if we actually need this. Checking via the controller probably
    provides enough insights into what nodes are doing.
    """
    errors = []
    warnings = []

    node_info = get_node_info(hostname)
    node_state = node_info["state"]

    return CheckResult(errors, warnings)


def check(log, hostname) -> CheckResult:
    results = []

    try:
        controller_names = pyslurm.get_controllers()
    except ValueError as e:
        return CheckResult(errors=[e.args[0]], warnings=[])

    if hostname in controller_names:
        results.append(check_controller(log, hostname))

    if hostname in NODE_API.get():
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
        "drain": len([1 for o in nodes if is_node_drain(o)]),
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
