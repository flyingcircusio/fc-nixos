import subprocess
import time
from unittest import mock

import fc.ceph.maintenance
import pytest


@pytest.fixture
def nosleep(monkeypatch):
    monkeypatch.setattr(time, "sleep", lambda x: None)


@pytest.fixture
def locktoolcalls(monkeypatch):
    locktoolcalls = mock.Mock()
    monkeypatch.setattr("fc.ceph.util.run.rbd_locktool", locktoolcalls)
    return locktoolcalls


@pytest.fixture
def rbdcalls(monkeypatch):
    rbdcalls = mock.Mock()
    monkeypatch.setattr("fc.ceph.util.run.rbd", rbdcalls)
    return rbdcalls


@pytest.fixture
def ceph_json_calls(monkeypatch):
    ceph_json_calls = mock.Mock()
    monkeypatch.setattr("fc.ceph.util.run.json.ceph", ceph_json_calls)
    return ceph_json_calls


def test_successful_maintenance_cycle(
    ceph_json_calls, locktoolcalls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        "",
        # leave
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-q", "-u", "rbd/.maintenance",
        "",
    ]
    ceph_json_calls.return_value = {
        "status": "HEALTH_OK",
    }

    maintenance_task.enter()
    maintenance_task.leave()

    assert ceph_json_calls.call_count == 1
    assert locktoolcalls.call_count == 4


def test_maintenance_enter_lock_timeout_causes_leave(
    rbdcalls, locktoolcalls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        subprocess.TimeoutExpired("rbd-locktool -l rbd/.maintenance", 30),
        # leave
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-q", "-u", "rbd/.maintenance",
        "",
    ]

    with pytest.raises(SystemExit, match="75") as exit_info:
        maintenance_task.enter()

    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-l", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )


def test_lockimage_created(
    locktoolcalls, rbdcalls, ceph_json_calls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    for opname in ["enter", "leave"]:
        locktoolcalls.side_effect = [
            # enter
            # "-q", "-i", "rbd/.maintenance"
            subprocess.CalledProcessError(1, "-q -i rbd/.maintenance"),
            # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
            "",
        ]
        rbdcalls.return_value = ""
        ceph_json_calls.return_value = {
            "status": "HEALTH_OK",
        }

        maintenance_task.__getattribute__(opname)()

        rbdcalls.assert_has_calls(
            [mock.call("create", "--size", "1", "rbd/.maintenance")]
        )


def test_tempfail_when_another_lockholder(locktoolcalls, maintenance_manager):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        subprocess.CalledProcessError(1, "-l rbd/.maintenance"),
        # leave
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-q", "-u", "rbd/.maintenance",
        "",
    ]

    with pytest.raises(SystemExit, match="75"):
        maintenance_task.enter()

    assert locktoolcalls.call_count == 2
    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-l", "rbd/.maintenance", timeout=30),
        ]
    )


def test_postpone_and_leave_when_unclean(
    locktoolcalls, ceph_json_calls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        "",
        # leave
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-q", "-u", "rbd/.maintenance",
        "",
    ]
    ceph_json_calls.return_value = {
        "status": "HEALTH_ERR",
    }

    with pytest.raises(SystemExit, match="69"):
        maintenance_task.enter()

    assert ceph_json_calls.call_count == 1
    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-l", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )


def test_leave_unlock_timeout_retries(
    locktoolcalls, nosleep, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = 4 * [
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        subprocess.TimeoutExpired("rbd-locktool -l rbd/.maintenance", 30),
    ] + [
        # "-q", "-i", "rbd/.maintenance"
        "",
        # successful unlock
        "",
    ]

    maintenance_task.leave()

    locktoolcalls.assert_has_calls(
        5
        * [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )

    assert locktoolcalls.call_count == 10


def test_leave_unlock_timeout_retries_exceeded(
    locktoolcalls, nosleep, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = 5 * [
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        subprocess.TimeoutExpired("rbd-locktool -l rbd/.maintenance", 30),
    ]

    with pytest.raises(subprocess.TimeoutExpired):
        maintenance_task.leave()

    locktoolcalls.assert_has_calls(
        5
        * [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )
    assert locktoolcalls.call_count == 10


def test_lockimage_check_timeout(locktoolcalls, maintenance_manager):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        subprocess.TimeoutExpired("rbd-locktool -l rbd/.maintenance", 30),
        # for simplicity, assume that unlock attempts do not time-out
        # leave
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-q", "-u", "rbd/.maintenance",
        "",
    ]

    with pytest.raises(SystemExit, match="75") as exit_info:
        maintenance_task.enter()

    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )

    assert locktoolcalls.call_count == 3


def test_check_cluster_maintenance(maintenance_manager):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    assert maintenance_task.check_cluster_maintenance(
        {
            "status": "HEALTH_OK",
        }
    )

    # some warnings can be ignored
    assert maintenance_task.check_cluster_maintenance(
        {
            "status": "HEALTH_WARN",
            "checks": {
                "PG_NOT_DEEP_SCRUBBED": "foo",
                "PG_NOT_SCRUBBED": "bar",
                "LARGE_OMAP_OBJECTS": "baz",
                "MANY_OBJECTS_PER_PG": "baozi",
            },
        }
    )

    # but some cannot
    assert not maintenance_task.check_cluster_maintenance(
        {
            "status": "HEALTH_WARN",
            "checks": {
                "PG_NOT_DEEP_SCRUBBED": "foo",
                "PG_NOT_SCRUBBED": "bar",
                "OSDMAP_FLAGS": {
                    "severity": "HEALTH_WARN",
                    "summary": {"message": "noout flag(s) set"},
                },
            },
        }
    )

    # and health errors always block maintenance
    assert not maintenance_task.check_cluster_maintenance(
        {
            "status": "HEALTH_ERR",
            "checks": {
                "PG_NOT_SCRUBBED": "bar",
            },
        }
    )
