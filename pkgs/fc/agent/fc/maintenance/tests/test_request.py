import datetime
import unittest.mock
from io import StringIO
from unittest.mock import MagicMock

import freezegun
import pytest
import pytz
import structlog
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.estimate import Estimate
from fc.maintenance.request import Attempt, Request, RequestMergeResult
from fc.maintenance.state import ARCHIVE, EXIT_TEMPFAIL, State
from fc.maintenance.tests import MergeableActivity
from rich.console import Console


def test_overdue_not_scheduled():
    r = Request(Activity(), 600)
    assert not r.overdue


@unittest.mock.patch("fc.maintenance.request.utcnow")
def test_overdue_before_due(utcnow):
    utcnow.side_effect = [
        datetime.datetime(2023, 1, 1, hour=0),
    ]
    r = Request(Activity(), 600)
    r.next_due = datetime.datetime(2023, 1, 1, hour=2)
    assert not r.overdue


@unittest.mock.patch("fc.maintenance.request.utcnow")
def test_overdue_after_but_ok(utcnow):
    utcnow.side_effect = [
        datetime.datetime(2023, 1, 1, hour=2, minute=19),
    ]
    r = Request(Activity(), 600)
    r.next_due = datetime.datetime(2023, 1, 1, hour=2)
    assert not r.overdue


@unittest.mock.patch("fc.maintenance.request.utcnow")
def test_overdue_thats_too_late(utcnow):
    utcnow.side_effect = [
        datetime.datetime(2023, 1, 1, hour=2, minute=31),
    ]
    r = Request(Activity(), 600)
    r.next_due = datetime.datetime(2023, 1, 1, hour=2)
    assert r.overdue


def test_duration():
    r = Request(Activity(), 1)
    a = Attempt()
    a.duration = 10
    r.attempts.append(a)
    a = Attempt()
    a.duration = 5
    r.attempts.append(a)
    assert r.duration == 5  # last attempt counts


@pytest.fixture
def logger():
    return structlog.get_logger()


@unittest.mock.patch("fc.maintenance.request.utcnow")
def test_duration_from_started_finished(utcnow, tmpdir):
    utcnow.side_effect = [
        datetime.datetime(2016, 4, 20, 6, 0),
        datetime.datetime(2016, 4, 20, 6, 2),
    ]
    r = Request(Activity(), 1, dir=str(tmpdir))
    r.execute()
    assert r.duration == 120.0


class FixedDurationActivity(Activity):
    def run(self):
        self.duration = 90
        self.returncode = 0


def test_duration_from_activity_duration(tmpdir):
    r = Request(FixedDurationActivity(), 1, dir=str(tmpdir))
    r.execute()
    assert r.duration == 90


def test_save_yaml(tmp_path):
    r = Request(Activity(), 10, "my comment", dir=str(tmp_path))
    assert r.id is not None
    r.save()
    saved_yaml = (tmp_path / "request.yaml").read_text()
    expected = f"""\
!!python/object:fc.maintenance.request.Request
_comment: my comment
_estimate: !!python/object:fc.maintenance.estimate.Estimate
  value: 10.0
_reqid: {r.id}
_reqmanager: null
activity: !!python/object:fc.maintenance.activity.Activity {{}}
added_at: null
attempts: []
dir: {tmp_path}
last_scheduled_at: null
next_due: null
state: !!python/object/apply:fc.maintenance.state.State
- '-'
updated_at: null
"""

    assert saved_yaml == expected


class TempfailActivity(Activity):
    def run(self):
        self.returncode = EXIT_TEMPFAIL


def test_execute_obeys_retrylimit(tmp_path):
    Request.MAX_RETRIES = 3
    r = Request(TempfailActivity(), dir=tmp_path)
    results = []
    for i in range(Request.MAX_RETRIES + 1):
        r.state = State.due
        r.execute()
        assert len(r.attempts) == i + 1
        r.update_state()
        results.append(r.state)
    assert results[0] == State.due
    assert results[-2] == State.due
    assert results[-1] == State.error


class FailingActivity(Activity):
    def run(self):
        raise RuntimeError("activity failing")


def test_execute_catches_errors(tmpdir):
    r = Request(FailingActivity(), 1, dir=str(tmpdir))
    r.execute()
    assert len(r.attempts) == 1
    assert "activity failing" in r.attempts[0].stderr
    assert r.attempts[0].returncode != 0


class ExternalStateActivity(Activity):
    def load(self):
        with open("external_state") as f:
            self.external = f.read()

    def dump(self):
        with open("external_state", "w") as f:
            print("foo", file=f)


def test_external_activity_state(tmpdir, logger):
    r = Request(ExternalStateActivity(), 1, dir=str(tmpdir))
    r.save()
    extstate = str(tmpdir / "external_state")
    with open(extstate) as f:
        assert "foo\n" == f.read()
    with open(extstate, "w") as f:
        print("bar", file=f)
    r2 = Request.load(str(tmpdir), logger)
    assert r2.activity.external == "bar\n"


def test_update_due_should_not_accept_naive_datetimes():
    r = Request(Activity(), 1)
    with pytest.raises(TypeError):
        r.update_due(datetime.datetime(2016, 4, 20, 12, 00))


def test_update_state_resets_invalid():
    r = Request(Activity())
    r.state = "obsolete"
    r.update_state()
    assert r.state == State.pending


@freezegun.freeze_time("2023-01-01 2:00:00")
def test_update_state_unchanged_when_not_due():
    r = Request(Activity())
    r.next_due = datetime.datetime(2023, 1, 1, hour=3, tzinfo=pytz.UTC)
    r.update_state()
    assert r.state == State.pending


@freezegun.freeze_time("2023-01-01 2:00:00")
def test_update_state_from_pending_to_due():
    r = Request(Activity())
    r.next_due = datetime.datetime(2023, 1, 1, hour=2, tzinfo=pytz.UTC)
    r.update_state()
    assert r.state == State.due


def test_update_state_from_postpone_to_pending():
    r = Request(Activity())
    r.state = State.postpone
    r.update_state()
    assert r.state == State.pending


def test_update_state_retrylimit():
    r = Request(Activity())
    r.state = State.due
    r.attempts = range(Request.MAX_RETRIES + 1)
    r.update_state()
    assert r.state == State.error


def test_update_state_doesnt_change_final_states():
    r = Request(Activity())
    for state in ARCHIVE:
        r.state = state
        r.update_state()
        assert r.state == state


def test_update_state_overdue_request(monkeypatch):
    r = Request(Activity())
    r.state = State.due
    monkeypatch.setattr("fc.maintenance.request.Request.overdue", True)
    r.update_state()
    assert r.state == State.postpone


def test_show():
    r = Request(Activity())
    r.activity.reboot_needed = RebootType.WARM

    console = Console(file=StringIO())
    console.print(r)
    out = console.file.getvalue()
    assert "fc.maintenance.activity.Activity (warm reboot needed)" in out


def test_merge(monkeypatch):
    monkeypatch.setattr(Request, "save", MagicMock())
    r = Request(MergeableActivity(), Estimate("20m"), "First request.")
    other = Request(MergeableActivity(), Estimate("10m"), "Other request")

    res = r.merge(other)
    assert res == RequestMergeResult.SIGNIFICANT_UPDATE
    assert r._comment == "First request.\n\nOther request"
    assert r._estimate == Estimate("20m")


def test_incompatible_activities_should_not_merge(monkeypatch):
    r = Request(MergeableActivity(), Estimate("20m"), "First request.")
    other = Request(Activity(), Estimate("10m"), "Other request")

    res = r.merge(other)
    assert res == RequestMergeResult.NO_MERGE


def test_merge_missing_comment_and_estimate_on_original_request(monkeypatch):
    monkeypatch.setattr(Request, "save", MagicMock())
    r = Request(MergeableActivity())
    other = Request(MergeableActivity(), Estimate("20m"), "Other request")

    r.merge(other)
    assert r._comment == "Other request"
    assert r._estimate == other.estimate
