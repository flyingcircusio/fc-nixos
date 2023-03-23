import sys
import unittest.mock
from itertools import chain, repeat
from unittest.mock import MagicMock

import pytest
from fc.util.logging import init_logging
from pytest import fixture, raises

pyslurm = type(sys)("pyslurm")
pyslurm.node = MagicMock()
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
pyslurm.version = lambda: "22.5.0"
sys.modules["pyslurm"] = pyslurm


init_logging(verbose=True, syslog_identifier="slurm-test")

import fc.util.slurm
from fc.util.slurm import NodeStateError, NodeStateTimeout, drain


@pytest.mark.parametrize(
    "state",
    ["IDLE+DRAIN", "ALLOCATED+DRAIN", "MIXED+DRAIN", "DOWN+DRAIN", "DOWN"],
)
@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_ready(update_nodes: MagicMock, get_node_info, state, logger):
    get_node_info.return_value = {"name": "test20", "state": state}
    fc.util.slurm.ready(logger, "test20")
    update_nodes.assert_called_once_with(
        {
            "node_names": "test20",
            "node_state": pyslurm.NODE_RESUME,
        }
    )


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_ready_noop(update_nodes: MagicMock, get_node_info, logger):
    get_node_info.return_value = {"name": "test20", "state": "IDLE"}
    fc.util.slurm.ready(logger, "test20")
    update_nodes.assert_not_called()


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_ready_offline(update_nodes: MagicMock, get_node_info, logger):
    get_node_info.return_value = {"name": "test20", "state": "IDLE*"}
    fc.util.slurm.ready(logger, "test20")
    update_nodes.assert_not_called()


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_down(update_nodes: MagicMock, get_node_info, logger, monkeypatch):
    get_node_info.return_value = {"name": "test20", "state": "IDLE+DRAIN"}
    fc.util.slurm.down(logger, "test20", "test down")
    update_nodes.assert_called_once_with(
        {
            "node_names": "test20",
            "node_state": pyslurm.NODE_STATE_DOWN,
            "reason": "test down",
        }
    )


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_down_noop(update_nodes: MagicMock, get_node_info, logger, monkeypatch):
    get_node_info.return_value = {"name": "test20", "state": "DOWN+DRAIN"}
    fc.util.slurm.down(logger, "test20", "test down noop")
    update_nodes.assert_not_called()


@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_drain(update_nodes, logger, monkeypatch):
    iter_states = iter(
        [
            "ALLOCATED",
            "MIXED+DRAIN",
            "IDLE+DRAIN",
        ]
    )

    def fake_get_node_info(node_name):
        return {
            "name": "test20",
            "state": next(iter_states),
        }

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    drain(logger, "test20", 3, "test drain")

    update_nodes.assert_called_once_with(
        {
            "node_names": "test20",
            "node_state": pyslurm.NODE_STATE_DRAIN,
            "reason": "test drain",
        }
    )


@unittest.mock.patch("fc.util.slurm.get_node_info")
@unittest.mock.patch("fc.util.slurm.update_nodes")
def test_drain_noop_when_already_drained(
    update_nodes: MagicMock, get_node_info, logger
):
    get_node_info.return_value = {
        "name": "test20",
        "state": "IDLE+DRAIN",
    }
    drain(logger, "test20", 3, "test drain")

    update_nodes.assert_not_called()


def test_drain_timeout(logger, monkeypatch):
    iter_states = chain(iter(["MIXED"]), repeat("MIXED+DRAIN"))

    def fake_get_node_info(node_name):
        return {
            "name": "test20",
            "state": next(iter_states),
        }

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)
    with raises(NodeStateTimeout) as e:
        drain(logger, "test20", 2, "test drain")

    assert e.value.remaining_node_states == {"test20": "MIXED+DRAIN"}


def test_drain_many_noop(logger, monkeypatch):
    def fake_get_node_info(node_name):
        return {"name": node_name, "state": "IDLE+DRAIN"}

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)

    fc.util.slurm.drain_many(logger, ["test20", "test21"], 3, "test drain noop")


def test_check_controller(logger):
    pyslurm.node.return_value.get.return_value = {
        "test20": {"state": "IDLE"},
        "test21": {"state": "ALLOCATED"},
        "test22": {"state": "MIXED"},
    }
    res = fc.util.slurm.check_controller(logger, "test20")
    assert res.errors == []
    assert res.warnings == []
    assert res.ok_info == [
        "All 3 nodes are operational.",
        "Running jobs: " "1.",
        "Pending jobs: 2.",
        "Total started jobs: 3.",
        "Slurm version: 22.5.0",
    ]


def test_check_controller_warning(logger):
    pyslurm.node.return_value.get.return_value = {
        "test20": {"state": "IDLE"},
        "test21": {"state": "ALLOCATED"},
        "test22": {"state": "MIXED"},
        "test23": {"state": "DOWN", "reason": "down"},
        "test24": {"state": "DOWN*", "reason": "down unresp"},
    }
    res = fc.util.slurm.check_controller(logger, "test20")
    assert res.errors == []
    assert res.warnings == [
        '2/5 nodes cannot accept jobs: test23 (DOWN, "down"), test24 (not '
        "responding)."
    ]


def test_check_controller_critical(logger):
    pyslurm.node.return_value.get.return_value = {
        "test22": {"state": "IDLE+DRAIN", "reason": "drain"},
        "test23": {"state": "DOWN", "reason": "down"},
        "test24": {"state": "DOWN*", "reason": "down unresp"},
    }
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
        return {
            "name": node_name,
            "state": next(iter_states[node_name]),
        }

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
        return {
            "name": node_name,
            "state": next(iter_states[node_name]),
        }

    monkeypatch.setattr(fc.util.slurm, "get_node_info", fake_get_node_info)

    with raises(NodeStateTimeout) as e:
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
