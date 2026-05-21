import subprocess
import time
import json
from unittest import mock
from subprocess import CalledProcessError

import pytest

# taken from a live nautilus cluster: `ceph --format=json-pretty health detail`
CEPH_HEALTH_NOUP_DATA = json.loads("""
{
    "checks": {
        "OSD_FLAGS": {
            "severity": "HEALTH_WARN",
            "summary": {
                "message": "3 OSDs or CRUSH {nodes, device-classes} have {NOUP,NODOWN,NOIN,NOOUT} flags set"
            },
            "detail": [
                {
                    "message": "osd.13 has flags noup"
                },
                {
                    "message": "osd.14 has flags noup"
                },
                {
                    "message": "osd.27 has flags noup"
                }
            ]
        }
    },
    "status": "HEALTH_WARN"
}
""")


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


@pytest.fixture
def ceph_calls(monkeypatch):
    ceph_calls = mock.Mock()
    ceph_calls.return_value = ""
    monkeypatch.setattr("fc.ceph.util.run.ceph", ceph_calls)
    return ceph_calls


def test_successful_maintenance_cycle(
    ceph_json_calls, ceph_calls, locktoolcalls, maintenance_manager, nosleep
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
    ceph_json_calls.side_effect = [
        {"status": "HEALTH_OK"},
        # osd tree
        {
            "nodes": [
                {"name": "localhost", "type": "host", "children": [14]},
                {
                    "name": "localhost-ssd",
                    "type": "host",
                    "children": [27, 13],
                },
            ]
        },
        # osd tree
        {
            "nodes": [
                {"name": "localhost", "type": "host", "children": [14]},
                {
                    "name": "localhost-ssd",
                    "type": "host",
                    "children": [27, 13],
                },
            ]
        },
        # health detail
        CEPH_HEALTH_NOUP_DATA,
    ]

    # (un)set-group and down commands

    maintenance_task.enter()
    maintenance_task.leave()

    assert ceph_json_calls.call_count == 4
    assert ceph_calls.call_count == 5
    assert locktoolcalls.call_count == 4

    ceph_calls.assert_has_calls(
        [
            mock.call("osd", "set-group", "noup", "13", "14", "27"),
            mock.call("osd", "down", "13", "14", "27"),
            mock.call("osd", "unset-group", "noup", "13"),
            mock.call("osd", "unset-group", "noup", "14"),
            mock.call("osd", "unset-group", "noup", "27"),
        ]
    )


def test_maintenance_enter_lock_timeout_causes_leave(
    rbdcalls, ceph_calls, ceph_json_calls, locktoolcalls, maintenance_manager
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

    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        {},
    ]

    with pytest.raises(SystemExit, match="75"):
        maintenance_task.enter()

    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-l", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )


def test_lockimage_created_on_enter(
    locktoolcalls, ceph_calls, rbdcalls, ceph_json_calls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    # Image gets created on `enter` path
    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        subprocess.CalledProcessError(1, "-q -i rbd/.maintenance"),
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        "",
    ]
    rbdcalls.return_value = ""
    ceph_json_calls.side_effect = [
        {"status": "HEALTH_OK"},
        # osd tree
        {"nodes": []},
    ]

    maintenance_task.enter()

    rbdcalls.assert_has_calls(
        [mock.call("create", "--size", "1", "rbd/.maintenance")]
    )


def test_lockimage_created_on_leave(
    locktoolcalls, ceph_calls, rbdcalls, ceph_json_calls, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    # Image gets created on `enter` path
    locktoolcalls.side_effect = [
        # enter
        # "-q", "-i", "rbd/.maintenance"
        subprocess.CalledProcessError(1, "-q -i rbd/.maintenance"),
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        "",
    ]
    rbdcalls.return_value = ""
    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        {},
    ]

    maintenance_task.leave()

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
    locktoolcalls, ceph_calls, ceph_json_calls, maintenance_manager
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
    ceph_json_calls.side_effect = [
        {"status": "HEALTH_ERR"},
        # osd tree
        {"nodes": []},
        # health detail
        {},
    ]

    with pytest.raises(SystemExit, match="69"):
        maintenance_task.enter()

    assert ceph_json_calls.call_count == 3
    locktoolcalls.assert_has_calls(
        [
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-l", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-i", "rbd/.maintenance", timeout=30),
            mock.call("-q", "-u", "rbd/.maintenance", timeout=30),
        ]
    )


def test_leave_unlock_timeout_retries(
    locktoolcalls, ceph_json_calls, ceph_calls, nosleep, maintenance_manager
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

    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        {},
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


def test_leave_filter_noup_exception_stay_locked(
    locktoolcalls, ceph_calls, ceph_json_calls, nosleep, maintenance_manager
):
    """If an exception during `filter_noup_osds` appears, the maintenance image
    stays locked and the exception bubbles up."""
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = []

    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        CalledProcessError("foo", cmd="ceph --format=json health detail"),
    ]

    with pytest.raises(CalledProcessError):
        maintenance_task.leave()

    assert locktoolcalls.call_count == 0


def test_leave_unlock_timeout_retries_exceeded(
    locktoolcalls, ceph_calls, ceph_json_calls, nosleep, maintenance_manager
):
    maintenance_task = maintenance_manager.MaintenanceTasks()

    locktoolcalls.side_effect = 5 * [
        # "-q", "-i", "rbd/.maintenance"
        "",
        # "-l", "rbd/.maintenance", timeout=self.LOCKTOOL_TIMEOUT_SECS
        subprocess.TimeoutExpired("rbd-locktool -l rbd/.maintenance", 30),
    ]

    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        {},
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


def test_lockimage_check_timeout(
    locktoolcalls, ceph_calls, ceph_json_calls, maintenance_manager
):
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

    ceph_json_calls.side_effect = [
        # osd tree
        {"nodes": []},
        # health detail
        {},
    ]

    with pytest.raises(SystemExit, match="75"):
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


def test_filter_noup_osds_has_matching_noup(
    ceph_json_calls, maintenance_manager_legacy
):
    ceph_json_calls.side_effect = [CEPH_HEALTH_NOUP_DATA, CEPH_HEALTH_NOUP_DATA]
    expected = set(("13", "14", "27"))
    assert maintenance_manager_legacy.filter_noup_osds(expected) == expected
    assert (
        maintenance_manager_legacy.filter_noup_osds(expected | set("5"))
        == expected
    )


def test_filter_noup_osds_has_mismatching_noup(
    ceph_json_calls, maintenance_manager_legacy
):
    ceph_json_calls.side_effect = [CEPH_HEALTH_NOUP_DATA]
    assert (
        maintenance_manager_legacy.filter_noup_osds(set(("21", "22", "23")))
        == set()
    )


def test_filter_noup_osds_empty(ceph_json_calls, maintenance_manager_legacy):
    ceph_json_calls.side_effect = [{}]
    assert (
        maintenance_manager_legacy.filter_noup_osds(set(("13", "14", "27")))
        == set()
    )


def test_filter_noup_osds_runtime_exception(
    ceph_json_calls, maintenance_manager_legacy
):
    ceph_json_calls.side_effect = [
        CalledProcessError("foo", cmd="ceph --format=json health detail")
    ]
    with pytest.raises(CalledProcessError):
        maintenance_manager_legacy.filter_noup_osds(set(("6", "8", "13")))
