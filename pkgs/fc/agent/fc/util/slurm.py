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


def drain(
    log,
    node_name,
    timeout: int,
    reason: str,
    nothing_to_do_is_ok: bool,
):
    log = log.bind(node=node_name)
    log.info("drain-start")
    node_info = get_node_info(node_name)
    node_state = node_info["state"]

    if "DRAIN" in node_state:
        if nothing_to_do_is_ok:
            log.info(
                "drain-already-reached",
                _replace_msg="Node is already in a draining state",
            )
            return
        else:
            log.error("drain-state-error", state=node_state)
            raise NodeStateError(node_state)

    if node_state == "DOWN":
        if nothing_to_do_is_ok:
            log.info(
                "drain-already-down",
                _replace_msg="Node {node} is already down",
            )
            return
        else:
            log.error("drain-state-error", state=node_state)
            raise NodeStateError(node_state)

    state_change_drain = {
        "node_names": node_name,
        "node_state": pyslurm.NODE_STATE_DRAIN,
        "reason": reason,
    }
    result = NODE_API.update(state_change_drain)
    log.debug("node-update-result", result=result)

    for ii in range(timeout):
        node_state = get_node_info(node_name)["state"]
        if node_state == "IDLE+DRAIN":
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
        _replace_msg="Node {node} is now marked as down",
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
                _replace_msg="Node {node} is already in a ready state",
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
