import json
import pytest

import freezegun

from datetime import date
from pathlib import Path
from unittest.mock import MagicMock, call
from fc.ceph.util.opslog import OpsLogState, OpsLog


@pytest.fixture
def state_file(tmpdir) -> Path:
    state_file = tmpdir / "opslog_state.json"
    with state_file.open("w") as f:
        f.write(json.dumps({"last_processed_datetime": "2025-01-01T01", "last_gced_day": "2024-12-28"}))

    return state_file


def test_opslog_state_rw(state_file):
    state = OpsLogState.read_from(state_file)
    assert state.last_gced_day.year == 2024
    assert state.last_gced_day.month == 12
    assert state.last_gced_day.day == 28
    assert state.last_processed_datetime.year == 2025
    assert state.last_processed_datetime.month == 1
    assert state.last_processed_datetime.day == 1
    assert state.last_processed_datetime.hour == 1
    assert state.last_processed_datetime.minute == 0

    state.last_gced_day = date(2025, 1, 2)
    state.write_to(state_file)

    with state_file.open("r") as f:
        raw = json.loads(f.read())

    assert raw['last_gced_day'] == "2025-01-02"


@pytest.fixture
def rados_log_objects(monkeypatch):
    mock = MagicMock(side_effect=[
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
            "2025-01-03-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo",
            "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring",
            "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo",
        ]
    ])
    monkeypatch.setattr(
        "fc.ceph.util.run.json.radosgw_admin", mock
    )

    return mock


@freezegun.freeze_time("2025-01-03 04:00")
def test_opslog_entries_by_day(state_file, rados_log_objects):
    opslog = OpsLog(state_file)

    with opslog.get_pending_stats_by_day() as log_objects:
        assert len(log_objects.keys()) == 3
        assert sorted(log_objects[date(2025, 1, 1)])[0] == "2025-01-01-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        assert len(log_objects[date(2025, 1, 1)]) == 4
        assert len(log_objects[date(2025, 1, 2)]) == 5
        assert len(log_objects[date(2025, 1, 3)]) == 4

        assert "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring" not in log_objects[date(2025, 1, 3)]
        assert "2025-01-03-04-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-foo" not in log_objects[date(2025, 1, 3)]

    rados_log_objects.assert_has_calls([
        call("log", "list", "--date=2025-01-01"),
        call("log", "list", "--date=2025-01-02"),
        call("log", "list", "--date=2025-01-03"),
    ])

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_gced_day"] == "2024-12-28"
        assert data["last_processed_datetime"] == "2025-01-03T03"


@freezegun.freeze_time("2025-01-01 04:00")
def test_start_end_same_day(state_file, rados_log_objects):
    opslog = OpsLog(state_file)

    with opslog.get_pending_stats_by_day() as log_objects:
        assert len(log_objects.keys()) == 1
        assert sorted(log_objects[date(2025, 1, 1)])[0] == "2025-01-01-02-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        assert log_objects[date(2025, 1, 1)][1] == "2025-01-01-03-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring"
        assert len(log_objects[date(2025, 1, 1)]) == 2

        assert "2025-01-01-01-720eae74-641a-4cdf-9838-f60d4a8751db.3474200421.1-rgw-monitoring" not in log_objects[date(2025, 1, 1)]

    rados_log_objects.assert_has_calls([
        call("log", "list", "--date=2025-01-01"),
    ])

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_gced_day"] == "2024-12-28"
        assert data["last_processed_datetime"] == "2025-01-01T03"


@freezegun.freeze_time("2025-01-03 04:00")
def test_opslog_entries_error_handling(state_file, rados_log_objects):
    opslog = OpsLog(state_file)

    class SpecialException(Exception):
        pass

    try:
        with opslog.get_pending_stats_by_day() as log_objects:
            raise SpecialException()
    except SpecialException:
        pass
    else:
        assert False, "Expected SpecialException being thrown from within the context manager"

    with state_file.open() as f:
        data = json.loads(f.read())
        assert data["last_processed_datetime"] == "2025-01-01T01"
