from typing import NamedTuple

import time

import pyslurm

NODE_API = pyslurm.node()

DOWN_STATES = ("DOWN", "POWERED_DOWN", "DOWN+DRAIN")
DRAIN_STATES = ("IDLE+DRAIN", "DRAINING", "DOWN+DRAIN")


class NodeStateError(Exception):
    def __init__(self, state):
        self.state = state


class NodeStateTimeout(Exception):
    def __init__(self, state):
        self.state = state


def get_node_info(node_name):
    return NODE_API.get_node(node_name)[node_name]


def get_all_node_names():
    return [k for k, v in NODE_API.get().items()]


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
