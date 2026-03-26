import json
import pytest
import IPy
import itertools

import freezegun

from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, call
from fc.ceph.util.opslog import OpsLogState, OpsLog


@pytest.fixture
def state_file(tmpdir) -> Path:
    state_file = tmpdir / "opslog_state.json"
    with state_file.open("w") as f:
        f.write(
            json.dumps(
                {
                    "last_processed_datetime": "2025-01-01T01",
                    "last_gced_day": "2024-12-28",
                }
            )
        )

    return state_file

def test_opslog_state_rw(state_file, tmpdir):
    with OpsLogState.open_locked(state_file, tmpdir) as state:
        assert state.last_gced_day.year == 2024
        assert state.last_gced_day.month == 12
        assert state.last_gced_day.day == 28
        assert state.last_processed_datetime.year == 2025
        assert state.last_processed_datetime.month == 1
        assert state.last_processed_datetime.day == 1
        assert state.last_processed_datetime.hour == 1
        assert state.last_processed_datetime.minute == 0

        state.last_gced_day = date(2025, 1, 2)

    with state_file.open("r") as f:
        raw = json.loads(f.read())

    assert raw["last_gced_day"] == "2025-01-02"


@pytest.fixture
def rados_log_objects(monkeypatch):
    mock = MagicMock(
        side_effect=[
            [
                "2025-01-01-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-05-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            ],
            [
                "2025-01-02-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-05-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            ],
            [
                "2025-01-03-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-03-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-03-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-03-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo_bar",
                "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo",
            ],
        ]
    )
    monkeypatch.setattr("fc.ceph.util.run.json.radosgw_admin", mock)

    return mock


@freezegun.freeze_time("2025-01-03 04:00")
def test_opslog_entries_by_day(state_file, rados_log_objects, tmpdir):
    opslog = OpsLog(state_file, tmpdir, [], [])

    with opslog.get_pending_stats_by_day() as log_objects:
        assert len(log_objects.keys()) == 3
        assert (
            sorted(log_objects[date(2025, 1, 1)])[0]
            == "2025-01-01-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        )
        assert len(log_objects[date(2025, 1, 1)]) == 4
        assert len(log_objects[date(2025, 1, 2)]) == 5
        assert len(log_objects[date(2025, 1, 3)]) == 4

        assert (
            "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            not in log_objects[date(2025, 1, 3)]
        )
        assert (
            "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo"
            not in log_objects[date(2025, 1, 3)]
        )

    rados_log_objects.assert_has_calls(
        [
            call("log", "list", "--date=2025-01-01"),
            call("log", "list", "--date=2025-01-02"),
            call("log", "list", "--date=2025-01-03"),
        ]
    )

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_gced_day"] == "2024-12-28"
        assert data["last_processed_datetime"] == "2025-01-03T03"


@freezegun.freeze_time("2025-01-01 04:00")
def test_start_end_same_day(state_file, rados_log_objects, tmpdir):
    opslog = OpsLog(state_file,tmpdir, [], [])

    with opslog.get_pending_stats_by_day() as log_objects:
        assert len(log_objects.keys()) == 1
        assert (
            sorted(log_objects[date(2025, 1, 1)])[0]
            == "2025-01-01-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        )
        assert (
            log_objects[date(2025, 1, 1)][1]
            == "2025-01-01-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        )
        assert len(log_objects[date(2025, 1, 1)]) == 2

        assert (
            "2025-01-01-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            not in log_objects[date(2025, 1, 1)]
        )

    rados_log_objects.assert_has_calls(
        [
            call("log", "list", "--date=2025-01-01"),
        ]
    )

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_gced_day"] == "2024-12-28"
        assert data["last_processed_datetime"] == "2025-01-01T03"


@pytest.fixture
def rados_log_objects_day_wrap(monkeypatch):
    def rgw_admin(*args, **kwargs):
        # Format: --date=YYYY-MM-DD
        day = args[-1].removeprefix("--date=2025-01-")
        if day == "01":
            return [
                "2025-01-01-21-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-22-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-01-23-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            ]
        elif day == "02":
            return [
                "2025-01-02-00-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
                "2025-01-02-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            ]
        return []

    mock = MagicMock(side_effect=rgw_admin)
    monkeypatch.setattr("fc.ceph.util.run.json.radosgw_admin", mock)

    return mock


def test_opslog_day_wrap(state_file, rados_log_objects_day_wrap, tmpdir):
    rados_log_objects = rados_log_objects_day_wrap
    opslog = OpsLog(state_file, tmpdir, [], [])

    def test_log_objects(
        expected_processed_day: str, expected_processed_hour: str
    ):
        with opslog.get_pending_stats_by_day() as log_objects:
            assert len(log_objects.keys()) == 1
            assert (
                len(log_objects[date(2025, 1, int(expected_processed_day))])
                == 1
            )
            assert (
                sorted(log_objects[date(2025, 1, int(expected_processed_day))])[
                    0
                ]
                == f"2025-01-{expected_processed_day}-{expected_processed_hour}-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            )

        rados_log_objects.assert_has_calls(
            [
                call("log", "list", f"--date=2025-01-{expected_processed_day}"),
            ]
        )

        with state_file.open() as f:
            data = json.loads(f.read())
            assert (
                data["last_processed_datetime"]
                == f"2025-01-{expected_processed_day}T{expected_processed_hour}"
            )

    with freezegun.freeze_time("2025-01-01 22:05"):
        test_log_objects("01", "21")

    with freezegun.freeze_time("2025-01-01 23:05"):
        test_log_objects("01", "22")

    with freezegun.freeze_time("2025-01-02 00:05"):
        test_log_objects("01", "23")

    with freezegun.freeze_time("2025-01-02 01:05"):
        test_log_objects("02", "00")

    with freezegun.freeze_time("2025-01-02 02:05"):
        test_log_objects("02", "01")


@pytest.fixture
def state_file_multiday(tmpdir) -> Path:
    state_file = tmpdir / "opslog_state.json"
    with state_file.open("w") as f:
        f.write(
            json.dumps(
                {
                    "last_processed_datetime": "2024-12-31T01",
                    "last_gced_day": "2024-12-28",
                }
            )
        )

    return state_file


@pytest.fixture
def rados_log_objects_multiday(monkeypatch):
    def rgw_admin(*args, **kwargs):
        # Format: --date=YYYY-MM-DD
        date = args[-1].removeprefix("--date=")
        if date == "2024-12-31":
            return [
                "2024-12-31-23-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            ]
        return [
            f"{date}-{str(hour).zfill(2)}-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            for hour in range(0, 24, 1)
        ]

    mock = MagicMock(side_effect=rgw_admin)
    monkeypatch.setattr("fc.ceph.util.run.json.radosgw_admin", mock)
    return mock


def test_opslog_multiday(state_file_multiday, rados_log_objects_multiday, tmpdir):
    state_file = state_file_multiday
    opslog = OpsLog(state_file, tmpdir, [], [])
    rados_log_objects = rados_log_objects_multiday

    def test_log_objects(expected_date: datetime):
        month_padded = str(expected_date.month).zfill(2)
        day_padded = str(expected_date.day).zfill(2)
        hour_padded = str(expected_date.hour).zfill(2)
        with opslog.get_pending_stats_by_day() as log_objects:
            assert len(log_objects.keys()) == 1
            assert (
                len(
                    log_objects[
                        date(
                            expected_date.year,
                            expected_date.month,
                            expected_date.day,
                        )
                    ]
                )
                == 1
            )
            assert (
                sorted(
                    log_objects[
                        date(
                            expected_date.year,
                            expected_date.month,
                            expected_date.day,
                        )
                    ]
                )[0]
                == f"{expected_date.year}-{month_padded}-{day_padded}-{hour_padded}-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
            )

        rados_log_objects.assert_has_calls(
            [
                call(
                    "log",
                    "list",
                    f"--date={expected_date.year}-{month_padded}-{day_padded}",
                ),
            ]
        )

        with state_file.open() as f:
            data = json.loads(f.read())
            assert (
                data["last_processed_datetime"]
                == f"{expected_date.year}-{month_padded}-{day_padded}T{hour_padded}"
            )

    for day, hour in itertools.product([1, 2, 3], range(0, 24, 1)):
        day_padded = str(day).zfill(2)
        hour_padded = str(hour).zfill(2)
        current_date = datetime(2025, 1, day, hour, 5)
        expected_date = current_date - timedelta(hours=1)
        with freezegun.freeze_time(current_date):
            test_log_objects(expected_date)


@freezegun.freeze_time("2025-01-03 04:00")
def test_opslog_entries_error_handling(state_file, rados_log_objects, tmpdir):
    opslog = OpsLog(state_file, tmpdir, [], [])

    class SpecialException(Exception):
        pass

    try:
        with opslog.get_pending_stats_by_day() as log_objects:
            raise SpecialException()
    except SpecialException:
        pass
    else:
        assert False, (
            "Expected SpecialException being thrown from within the context manager"
        )

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_processed_datetime"] == "2025-01-01T01"


@pytest.fixture
def get_object_mock(monkeypatch):
    internal_networks = list(
        map(
            IPy.IP,
            [
                "10.0.0.0/8",
                "fd42:23::/48",
            ],
        )
    )
    rgw_location_proxy_ips = list(
        map(
            IPy.IP,
            [
                "fd42:23::abc",
                "192.168.0.1",
                "10.0.1.2",
                "fd42:23::1"
            ],
        )
    )
    mock = MagicMock(
        side_effect=[
            {
                "bucket_id": "12345",
                "bucket_owner": "test",
                "bucket": "test",
                "log_entries": [
                    # internal traffic gets filtered out
                    {
                        "remote_addr": "fd42:23::abc",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                    },
                    # external traffic is kept
                    {
                        "remote_addr": "192.168.0.1",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                    },
                    # X-Real-IP always takes precedence
                    {
                        "remote_addr": "192.168.0.1",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                        "http_x_headers": [{"HTTP_X_REAL_IP": "10.0.1.2"}],
                    },
                    {
                        "remote_addr": "10.0.1.2",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                        "http_x_headers": [{"HTTP_X_REAL_IP": "10.0.1.3"}],
                    },
                    {
                        "remote_addr": "10.0.1.2",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                        "http_x_headers": [{"HTTP_X_REAL_IP": "192.168.0.1"}],
                    },
                    # Same for IPv6
                    {
                        "remote_addr": "fd42:23::1",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                        "http_x_headers": [
                            {"HTTP_X_REAL_IP": "2a01:4f8:f00::1"}
                        ],
                    },
                    {
                        "remote_addr": "fd42:23::1",
                        "bucket": "test",
                        "bytes_sent": 23,
                        "bytes_received": 42,
                        "http_x_headers": [{"HTTP_X_REAL_IP": "fd42:23::1"}],
                    },
                ],
                "log_sum": {"something": "in here"},
            }
        ]
    )
    monkeypatch.setattr("fc.ceph.util.run.json.radosgw_admin", mock)

    return mock, internal_networks, rgw_location_proxy_ips


def test_opslog_object_with_filtered_ips(get_object_mock, state_file, tmpdir):
    mock, internal_networks, rgw_location_proxy_ips = get_object_mock
    opslog = OpsLog(state_file,tmpdir, internal_networks, rgw_location_proxy_ips)

    result = opslog.get_object("foo")
    mock.assert_has_calls(
        [
            call("log", "show", "--object=foo"),
        ]
    )

    assert "log_sum" not in result
    assert all(
        x in result
        for x in [
            "bucket_id",
            "bucket_owner",
            "bucket",
            "log_entries",
        ]
    )

    entries = result["log_entries"]
    assert len(entries) == 3

    assert entries[0]["remote_addr"] == "192.168.0.1"
    assert entries[1]["remote_addr"] == "10.0.1.2"
    assert entries[1]["http_x_headers"][0]["HTTP_X_REAL_IP"] == "192.168.0.1"
    assert entries[2]["remote_addr"] == "fd42:23::1"
    assert (
        entries[2]["http_x_headers"][0]["HTTP_X_REAL_IP"] == "2a01:4f8:f00::1"
    )

def test_opslog_object_with_filtered_rgw_location_proxy(get_object_mock, state_file, tmpdir):
    mock, _, _ = get_object_mock
    internal_networks = []
    rgw_location_proxy_ips = [
        IPy.IP("10.0.1.2"),
        IPy.IP("fd42:23::abc")
    ]
    opslog = OpsLog(state_file, tmpdir, internal_networks, rgw_location_proxy_ips)

    result = opslog.get_object("foo")
    mock.assert_has_calls(
        [
            call("log", "show", "--object=foo"),
        ]
    )

    assert "log_sum" not in result
    assert all(
        x in result
        for x in [
            "bucket_id",
            "bucket_owner",
            "bucket",
            "log_entries",
        ]
    )

    entries = result["log_entries"]
    assert len(entries) == 3
    for entry in entries:
        assert IPy.IP(entry["remote_addr"]) in rgw_location_proxy_ips
