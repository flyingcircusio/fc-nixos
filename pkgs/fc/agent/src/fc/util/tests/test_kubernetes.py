import subprocess
import sys
import unittest.mock
from unittest.mock import MagicMock, Mock

from fc.util.logging import init_logging
from fc.util.tests import PollingFakePopen
from pytest import raises

init_logging(verbose=True, syslog_identifier="kubernetes-test")

import fc.util.kubernetes
from fc.util.kubernetes import DrainingAction, NodeDrainTimeout


def fake_metadata(name, **kwargs):
    return {
        "name": name,
        "annotations": {},
        "labels": {},
        **kwargs,
    }


@unittest.mock.patch("fc.util.kubernetes.get_node")
@unittest.mock.patch("subprocess.run")
def test_uncordon(run: MagicMock, get_node, logger, log):
    get_node.return_value = {
        "spec": {"unschedulable": True},
        "metadata": fake_metadata(
            "test20", labels={"fcio.net/maintenance": "test"}
        ),
    }
    fc.util.kubernetes.uncordon(logger, "test20", label_must_match="test")
    run.assert_any_call(
        [
            "k3s",
            "kubectl",
            "--kubeconfig",
            "/var/lib/k3s/agent/kubelet.kubeconfig",
            "uncordon",
            "test20",
        ]
    )
    assert log.has("ready-pre-doit")
    assert log.has("ready-finished")


@unittest.mock.patch("fc.util.kubernetes.get_node")
@unittest.mock.patch("subprocess.run")
def test_uncordon_noop_when_already_ready(run, get_node, logger, log):
    get_node.return_value = {
        "spec": {},
        "metadata": fake_metadata("test20"),
    }
    fc.util.kubernetes.uncordon(logger, "test20")
    run.assert_not_called()
    assert log.has("ready-already-reached")


@unittest.mock.patch("fc.util.kubernetes.get_node")
@unittest.mock.patch("subprocess.run")
def test_uncordon_noop_when_label_not_matched(run, get_node, logger, log):
    get_node.return_value = {
        "spec": {"unschedulable": True},
        "metadata": fake_metadata(
            "test20", labels={"fcio.net/maintenance": "wronglabel"}
        ),
    }
    fc.util.kubernetes.uncordon(logger, "test20", label_must_match="test")
    run.assert_not_called()
    assert log.has("ready-pre-label-not-matched")


@unittest.mock.patch("fc.util.kubernetes.run_drain_pre_checks")
@unittest.mock.patch("subprocess.run")
def test_drain(run, run_drain_pre_checks, logger, monkeypatch):
    run_drain_pre_checks.return_value = DrainingAction.DRAIN

    kubectl_drain_fake = PollingFakePopen(
        "drain",
        stdout="Draining...",
        returncode=0,
    )

    popen = Mock(return_value=kubectl_drain_fake)
    monkeypatch.setattr("subprocess.Popen", popen)

    fc.util.kubernetes.drain(logger, "test20", 3, "testdrain")

    run.assert_any_call(
        [
            "k3s",
            "kubectl",
            "--kubeconfig",
            "/var/lib/k3s/agent/kubelet.kubeconfig",
            "label",
            "node",
            "test20",
            "fcio.net/maintenance=testdrain",
        ],
        check=True,
    )

    popen.assert_called_with(
        [
            "k3s",
            "kubectl",
            "--kubeconfig",
            "/var/lib/k3s/agent/kubelet.kubeconfig",
            "drain",
            "test20",
            "--delete-emptydir-data",
            "--ignore-daemonsets",
            "--timeout=3s",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


@unittest.mock.patch("fc.util.kubernetes.get_node")
@unittest.mock.patch("subprocess.Popen")
def test_drain_noop(popen: MagicMock, get_node, logger):
    get_node.return_value = {
        "spec": {"unschedulable": True},
        "metadata": fake_metadata("test20"),
    }
    fc.util.kubernetes.drain(logger, "test20", 3, "test drain")
    popen.assert_not_called()


@unittest.mock.patch("fc.util.kubernetes.run_drain_pre_checks")
def test_drain_wait_timeout(run_drain_pre_checks, logger, log, monkeypatch):
    run_drain_pre_checks.return_value = DrainingAction.WAIT

    kubectl_drain_fake = PollingFakePopen(
        "drain-timeout",
        stdout="global timeout reached",
        returncode=1,
    )

    popen = Mock(return_value=kubectl_drain_fake)
    monkeypatch.setattr("subprocess.Popen", popen)

    with raises(NodeDrainTimeout) as e:
        fc.util.kubernetes.drain(logger, "test20", 2, "test drain")

    assert log.has("drain-timeout")
