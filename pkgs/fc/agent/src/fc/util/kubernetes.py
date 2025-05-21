import json
import subprocess
from enum import Enum
from typing import NamedTuple, Optional

from fc.util.directory import is_node_in_service
from fc.util.subprocess_helper import get_popen_stdout_lines

MAINT_LABEL_NAME = "fcio.net/maintenance"

SERVER_TAINT = {
    "effect": "NoSchedule",
    "key": "node-role.kubernetes.io/server",
    "value": "true",
}


class NodeStateError(Exception):
    pass


class NodeDrainError(Exception):
    pass


class NodeDrainTimeout(NodeDrainError):
    pass


class DrainingAction(Enum):
    NO_OP = 0
    DRAIN = 1
    WAIT = 2


def is_node_ready(node: dict):
    spec = node["spec"]
    return "unschedulable" not in spec or not spec["unschedulable"]


def is_node_drained(log, node: dict):
    spec = node["spec"]
    metadata = node["metadata"]
    log.debug(
        "is-node-drained",
        node=metadata["name"],
        annotations=metadata["annotations"],
    )
    return "unschedulable" in spec and spec["unschedulable"]


def is_agent_node(node: dict):
    return SERVER_TAINT not in node["spec"].get("taints", [])


def kubectl(
    *varargs,
    json_output=False,
):
    args = [
        "k3s",
        "kubectl",
        "--kubeconfig",
        "/var/lib/k3s/agent/kubelet.kubeconfig",
        *varargs,
    ]
    if json_output:
        args.extend(["-o", "json"])

    return args


def get_node(node_name) -> dict:
    jso = subprocess.run(
        kubectl("get", "node", node_name, json_output=True),
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    return json.loads(jso)


def get_agent_nodes() -> list[dict]:
    jso = subprocess.run(
        kubectl("get", "nodes", json_output=True),
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    nodes = json.loads(jso)["items"]

    return [node for node in nodes if is_agent_node(node)]


def get_all_agent_node_names() -> list[str]:
    return [ni["metadata"]["name"] for ni in get_agent_nodes()]


def run_drain_pre_checks(log, node_name, strict_state_check):
    log = log.bind(node=node_name)

    node = get_node(node_name)

    if not is_agent_node(node):
        if strict_state_check:
            log.error("drain-pre-check-state-error", reason="no agent")
            raise NodeStateError("Node is not an agent.")
        else:
            log.info(
                "drain-pre-check-no-agent",
                _replace_msg=(
                    "Draining a non-agent node is unnecessary. No action."
                ),
            )
            return DrainingAction.NO_OP

    if is_node_drained(log.bind(op="pre-check"), node):
        if strict_state_check:
            log.error("drain-pre-check-state-error", reason="drained")
            raise NodeStateError("Node is already drained.")
        else:
            log.info(
                "drain-pre-already-drained",
                _replace_msg="{node} is already drained. No action.",
            )
            return DrainingAction.NO_OP

    log.info(
        "drain-pre-needs-draining",
        _replace_msg="{node} needs draining.",
    )

    return DrainingAction.DRAIN


def drain(
    log,
    node_name,
    timeout: int,
    maintenance_label: str,
    strict_state_check: bool = False,
):
    log = log.bind(node=node_name)
    log.debug(
        "drain-start",
        timeout=timeout,
        maintenance_label=maintenance_label,
        strict_state_check=strict_state_check,
    )

    drain_action = run_drain_pre_checks(log, node_name, strict_state_check)

    match drain_action:
        case DrainingAction.NO_OP:
            return

        case DrainingAction.DRAIN:
            label = f"fcio.net/maintenance={maintenance_label}"
            subprocess.run(
                kubectl("label", "node", node_name, label),
                check=True,
            )
        case DrainingAction.WAIT:
            log.info(
                "node-drain-wait",
                _replace_msg=(
                    "Node already has the maintenance label from a previous run "
                    "which ran into a timeout or was interrupted. "
                    "Waiting for the node to fully drain."
                ),
            )

    log.debug("kubectl-drain-start")
    proc = subprocess.Popen(
        kubectl(
            "drain",
            node_name,
            "--delete-emptydir-data",
            "--ignore-daemonsets",
            f"--timeout={timeout}s",
        ),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    stdout_lines = get_popen_stdout_lines(proc, log, "kubectl-drain-out")
    stdout = "".join(stdout_lines)
    proc.wait()

    if proc.returncode == 0:
        log.info(
            "drain-finished",
        )
    elif "global timeout reached" in stdout:
        log.error(
            "drain-timeout",
            _replace_msg=(
                "{node} did not finish draining in time, waited {timeout} "
                "seconds."
            ),
            timeout=timeout,
            stdout=stdout,
        )
        raise NodeDrainTimeout()
    else:
        log.error("drain-failed", returncode=proc.returncode, stdout=stdout)
        raise NodeDrainError()


class ReadyPreCheckResult(NamedTuple):
    state: str
    action: bool


def run_ready_pre_checks(
    log,
    node_name,
    strict_state_check,
    label_must_match,
    skip_in_maintenance,
    directory,
):
    log = log.bind(node=node_name)
    node = get_node(node_name)
    log.debug("ready-pre-node-state", metadata=node.get("metadata"))

    if is_node_ready(node):
        if strict_state_check:
            log.error("ready-state-error")
            raise NodeStateError("Node is already ready.")
        else:
            log.info(
                "ready-already-reached",
                _replace_msg="{node} is already ready. No action.",
            )
            return ReadyPreCheckResult("ready", action=False)

    maint_label = node["metadata"]["labels"].get(MAINT_LABEL_NAME)

    if label_must_match:
        if maint_label is None or label_must_match not in maint_label:
            log.info(
                "ready-pre-label-not-matched",
                _replace_msg=(
                    "{node} cannot be set to ready because the maintenance "
                    "label does not contain the expected string: "
                    "expected: '{expected}', actual: '{maint_label}'"
                ),
                expected=label_must_match,
                maint_label=maint_label,
            )
            return ReadyPreCheckResult("drained", action=False)

    if skip_in_maintenance and not is_node_in_service(directory, node_name):
        log.info(
            "ready-pre-not-in-service",
            node=node_name,
            _replace_msg="{node} is still in maintenance, skipping.",
        )
        return ReadyPreCheckResult("drained", action=False)

    log.info(
        "ready-pre-doit",
        _replace_msg="{node} can be set to ready.",
    )
    return ReadyPreCheckResult("drained", action=True)


def uncordon(
    log,
    node_name,
    strict_state_check: bool = False,
    label_must_match: Optional[str] = None,
    skip_in_maintenance=False,
    directory=None,
):
    log = log.bind(node=node_name)
    log.debug("ready-start")

    result = run_ready_pre_checks(
        log,
        node_name,
        strict_state_check,
        label_must_match,
        skip_in_maintenance,
        directory,
    )

    if not result.action:
        return

    result = subprocess.run(kubectl("uncordon", node_name))
    log.debug("node-uncordon-result", result=result)

    subprocess.run(
        kubectl("label", "node", node_name, MAINT_LABEL_NAME + "-"),
        check=True,
    )

    log.info(
        "ready-finished",
        _replace_msg="{node} set to ready (uncordoned).",
    )
