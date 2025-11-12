import sys
import unittest.mock
from itertools import chain, repeat
from textwrap import dedent
from unittest.mock import MagicMock

import pytest

from fc.util.logging import init_logging


class Node:
    def __init__(self, **kwargs):
        self.__dict__.update(**kwargs)

    def __eq__(self, other_node):
        print(other_node.__dict__)
        return self.__dict__ == other_node.__dict__

    def __repr__(self):
        return f"<Node({str(self.__dict__)})>"

    @classmethod
    def load(cls, name):
        return cls(name=name)

    def modify(self, *args):
        pass

# We cannot import pyslurm, as it just exits with error 1 when it has no slurm cluster
pyslurm = type(sys)("pyslurm")
pyslurm.Nodes = MagicMock()
pyslurm.Node = Node
pyslurm.get_controllers = MagicMock()
pyslurm.NODE_STATE_DRAIN = 1
pyslurm.NODE_STATE_DOWN = 2
pyslurm.NODE_RESUME = 3
pyslurm.slurm_ping = MagicMock()
pyslurm.statistics = MagicMock()
pyslurm.statistics.return_value.get.return_value = {
    "jobs_running": 1,
    "jobs_pending": 2,
    "jobs_started": 3,
}
pyslurm.version = type(sys)("pyslurm.version")
pyslurm.version.__version__ = "24.11.0"
sys.modules["pyslurm"] = pyslurm

init_logging(verbose=True, syslog_identifier="slurm-test")

import fc.util.slurm
from fc.util.slurm import NodeStateTimeout


@pytest.mark.parametrize(
    "state",
    ["IDLE+DRAIN", "ALLOCATED+DRAIN", "MIXED+DRAIN", "DOWN+DRAIN", "DOWN"],
)
@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_ready(modify_node: MagicMock, get_node_info, state, logger):
    get_node_info.return_value = Node(name="test20", state=state)
    fc.util.slurm.ready(logger, "test20")
    modify_node.assert_called_once_with("test20", Node(state="RESUME"))


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_ready_noop(modify_node: MagicMock, get_node_info, logger):
    get_node_info.return_value = Node(name="test20", state="IDLE")
    fc.util.slurm.ready(logger, "test20")
    modify_node.assert_not_called()


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_ready_offline(modify_node: MagicMock, get_node_info, logger):
    get_node_info.return_value = Node(name="test20", state="IDLE*")
    fc.util.slurm.ready(logger, "test20")
    modify_node.assert_not_called()


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_down(modify_node: MagicMock, get_node_info, logger, monkeypatch):
    get_node_info.return_value = Node(name="test20", state="IDLE+DRAIN")
    fc.util.slurm.down(logger, "test20", "test down")
    modify_node.assert_called_once_with(
        "test20", Node(state="DOWN", reason="test down")
    )


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_down_noop(modify_node: MagicMock, get_node_info, logger, monkeypatch):
    get_node_info.return_value = Node(name="test20", state="DOWN+DRAIN")
    fc.util.slurm.down(logger, "test20", "test down noop")
    modify_node.assert_not_called()


@unittest.mock.patch("fc.util.slurm.modify_node")
def test_drain(modify_node, logger, monkeypatch):
    iter_states = iter(
        [
            "ALLOCATED",
            "MIXED+DRAIN",
            "IDLE+DRAIN",
        ]
    )

    def fake_get_node_info(node_name):
        return Node(name="test20", state=next(iter_states))

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    fc.util.slurm.drain(logger, "test20", 3, "test drain")

    modify_node.assert_called_once_with(
        "test20", Node(state="DRAIN", reason="test drain")
    )


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.modify_node")
def test_drain_noop_when_already_drained(
    modify_node: MagicMock, get_node_info, logger
):
    get_node_info.return_value = Node(name="test20", state="IDLE+DRAIN")
    fc.util.slurm.drain(logger, "test20", 3, "test drain")
    modify_node.assert_not_called()


def test_drain_timeout(logger, monkeypatch):
    iter_states = chain(iter(["MIXED"]), repeat("MIXED+DRAIN"))

    def fake_get_node_info(node_name):
        return Node(name="test20", state=next(iter_states))

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    with pytest.raises(NodeStateTimeout) as e:
        fc.util.slurm.drain(logger, "test20", 2, "test drain")

    assert e.value.remaining_node_states == {"test20": "MIXED+DRAIN"}


def test_drain_many_noop(logger, monkeypatch):
    def fake_get_node_info(node_name):
        return Node(name=node_name, state="IDLE+DRAIN")

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    fc.util.slurm.drain_many(logger, ["test20", "test21"], 3, "test drain noop")


def test_check_controller(logger):
    pyslurm.Nodes.load.return_value.items.return_value = {
        "test20": Node(name="test20", state="IDLE"),
        "test21": Node(name="test21", state="ALLOCATED"),
        "test22": Node(name="test22", state="MIXED"),
    }.items()
    res = fc.util.slurm.check_controller(logger, "test20")
    assert res.errors == []
    assert res.warnings == []
    assert res.ok_info == [
        "All 3 nodes are operational.",
        "Running jobs: 1.",
        "Pending jobs: 2.",
        "Total started jobs: 3.",
        "Slurm version: 24.11.0",
    ]


def test_check_controller_warning(logger):
    pyslurm.Nodes.load.return_value.items.return_value = {
        "test20": Node(name="test20", state="IDLE"),
        "test21": Node(name="test21", state="ALLOCATED"),
        "test22": Node(name="test22", state="MIXED"),
        "test23": Node(name="test23", state="DOWN", reason="down"),
        "test24": Node(name="test24", state="DOWN*", reason="down unresp")
    }.items()
    res = fc.util.slurm.check_controller(logger, "test20")
    assert res.errors == []
    assert res.warnings == [
        '2/5 nodes cannot accept jobs: test23 (DOWN, "down"), test24 (not '
        "responding)."
    ]


def test_check_controller_critical(logger):
    pyslurm.Nodes.load.return_value.items.return_value = {
        "test22": Node(name="test22", state="IDLE+DRAIN", reason="drain"),
        "test23": Node(name="test23", state="DOWN", reason="down"),
        "test24": Node(name="test24", state="DOWN*", reason="down unresp"),
    }.items()
    res = fc.util.slurm.check_controller(logger, "test20")
    assert res.errors == [
        "All nodes cannot accept jobs: "
        'test22 (IDLE+DRAIN, "drain"), '
        'test23 (DOWN, "down"), '
        "test24 (not responding)."
    ]


def test_drain_many(logger, monkeypatch):
    iter_states = {
        "test20": iter(
            [
                "ALLOCATED+DRAIN",
                "MIXED+DRAIN",
                "IDLE+DRAIN",
                "IDLE+DRAIN",
            ]
        ),
        "test21": iter(
            [
                "MIXED",
                "MIXED+DRAIN",
                "IDLE+DRAIN",
            ]
        ),
        "test22": iter(
            [
                "IDLE",
                "IDLE+DRAIN",
            ]
        ),
        "test23": iter(
            [
                "IDLE+DRAIN",
            ]
        ),
        "test24": iter(
            [
                "IDLE*",
                "IDLE*+DRAIN",
            ]
        ),
        "test25": iter(
            [
                "DOWN",
                "DOWN+DRAIN",
            ]
        ),
        "test26": iter(
            [
                "DOWN*",
                "DOWN*+DRAIN",
            ]
        ),
        "test27": iter(
            [
                "ALLOCATED*",
                "ALLOCATED*+DRAIN",
                "IDLE+DRAIN",
            ]
        ),
    }

    def fake_get_node_info(node_name):
        return Node(name=node_name, state=next(iter_states[node_name]))
    
    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    fc.util.slurm.drain_many(
        logger, list(iter_states.keys()), 3, "test drain many"
    )


def test_drain_many_timeout(logger, log, monkeypatch):
    iter_states = {
        "test20": iter(
            [
                "ALLOCATED+DRAIN",
                "MIXED+DRAIN",
                "IDLE+DRAIN",
                "IDLE+DRAIN",
            ]
        ),
        "test21": iter(
            [
                "IDLE+DRAIN",
            ]
        ),
        "test22": chain(
            iter(["MIXED"]),
            repeat("MIXED+DRAIN"),
        ),
    }

    def fake_get_node_info(node_name):
        return Node(name=node_name, state=next(iter_states[node_name]))

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)

    with pytest.raises(NodeStateTimeout) as e:
        fc.util.slurm.drain_many(
            logger, list(iter_states.keys()), 3, "test drain many timeout"
        )

    remaining_node_states = {"test22": "MIXED+DRAIN"}

    assert e.value.remaining_node_states == remaining_node_states

    assert log.has(
        "drain-many-timeout",
        timeout=3,
        remaining_node_states=remaining_node_states,
    )


def test_ready_many(logger, monkeypatch):
    iter_states = {
        "test20": iter(
            [
                "IDLE+DRAIN",
                "IDLE",
            ]
        ),
        "test21": iter(
            [
                "DOWN+DRAIN",
                "MIXED",
            ]
        ),
        "test22": iter(
            [
                "DOWN",
                "IDLE",
            ]
        ),
        "test23": iter(
            [
                "IDLE",
            ]
        ),
        "test24": iter(
            [
                "IDLE*",
                "IDLE",
            ]
        ),
        # Node is DOWN forever.
        "test25": repeat("DOWN"),
    }

    # test25 should be ignored by ready_many. It would cause a timeout if the function
    # fails to ignore it because the node will never be in a ready state.

    def fake_get_node_info(node_name):
        return Node(name=node_name, state=next(iter_states[node_name]), reason="other" if node_name == "test25" else "test ready many")

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    fc.util.slurm.ready_many(
        logger,
        list(iter_states.keys()),
        3,
        reason_must_match="test ready many",
    )


def test_ready_many_timeout(logger, log, monkeypatch):
    iter_states = {
        "test20": iter(
            [
                "IDLE+DRAIN",
                "IDLE",
            ]
        ),
        "test21": iter(
            [
                "IDLE",
            ]
        ),
        # Node is DOWN forever.
        "test22": repeat("DOWN"),
    }

    def fake_get_node_info(node_name):
        return Node(name=node_name, state=next(iter_states[node_name]), reason="test ready many timeout")

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)

    with pytest.raises(NodeStateTimeout) as e:
        fc.util.slurm.ready_many(
            logger,
            list(iter_states.keys()),
            3,
            reason_must_match="test ready many timeout",
        )

    remaining_node_states = {"test22": "DOWN"}

    assert e.value.remaining_node_states == remaining_node_states

    assert log.has(
        "ready-many-timeout",
        timeout=3,
        remaining_node_states=remaining_node_states,
    )


def test_fc_slurm_check_returns_fallback_warning_on_no_data(logger):
    from fc.util.checks import CheckResult

    pyslurm.Nodes.load.return_value.keys.return_value = [
        "test20",
        "test21",
        "test22"
    ]
    pyslurm.Nodes.load.return_value.items.return_value = {
        "test20": Node(name="test20", state="IDLE"),
        "test21": Node(name="test21", state="ALLOCATED"),
        "test22": Node(name="test22", state="MIXED")
    }.items()

    pyslurm.Nodes.load.return_value.get.side_effect = lambda node_name: {
        "test20": Node(name="test20", state="IDLE"),
        "test21": Node(name="test21", state="ALLOCATED"),
        "test22": Node(name="test22", state="MIXED")
    }[node_name]
    pyslurm.get_controllers.return_value = ["test20"]

    check_result = fc.util.slurm.check("logger", "somehost")

    assert check_result == CheckResult(
        errors=[],
        ok_info=[],
        warnings=[
            dedent(
                """\
                No data available for this node `somehost`. Is this a `slurm-node`?
                Got data for nodes ['test20', 'test21', 'test22']."""
            )
        ],
    )
