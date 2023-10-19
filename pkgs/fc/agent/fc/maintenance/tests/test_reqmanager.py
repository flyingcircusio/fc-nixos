import datetime
import os
import os.path as p
import socket
import textwrap
import unittest.mock
from io import StringIO
from unittest.mock import MagicMock, Mock, call

import freezegun
import pytest
import pytz
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.estimate import Estimate
from fc.maintenance.reqmanager import (
    PostponeMaintenance,
    ReqManager,
    TempfailMaintenance,
)
from fc.maintenance.request import Attempt, Request
from fc.maintenance.state import ARCHIVE, EXIT_POSTPONE, State
from fc.maintenance.tests import MergeableActivity
from fc.util.time_date import utcnow
from rich.console import Console


@pytest.fixture
def agent_maintenance_config(tmp_path):
    config_path = tmp_path / "fc-agent.conf"
    config_path.write_text(
        textwrap.dedent(
            """\
            [maintenance]
            preparation_seconds = 300

            [maintenance-enter]
            demo = echo "entering demo"

            [maintenance-leave]
            demo = echo "leaving demo"
            dummy =
            """
        )
    )
    return config_path


def test_init_should_create_directories(reqmanager):
    spooldir = reqmanager.spooldir
    assert p.isdir(spooldir)
    assert p.isdir(p.join(spooldir, "requests"))
    assert p.isdir(p.join(spooldir, "archive"))


def test_lockfile(reqmanager):
    with reqmanager:
        # ReqManager active, lock file contain PID
        assert (reqmanager.spooldir / ".lock").read_text().strip() == str(
            os.getpid()
        )

    # ReqManager closed, lock file should be empty now.
    assert (reqmanager.spooldir / ".lock").read_text() == ""


def test_req_save(request_population):
    with request_population(1) as (rm, requests):
        req = requests[0]
        assert p.isfile(p.join(req.dir, "request.yaml"))
        print(open(p.join(req.dir, "request.yaml")).read())


class FunnyActivity(Activity):
    def __init__(self, mood):
        super().__init__()
        self.mood = mood


def test_scan(request_population):
    with request_population(3) as (rm, requests):
        requests[0]._comment = "foo"
        requests[0].save()
        requests[1].activity = FunnyActivity("good")
        requests[1].save()
    with rm:
        assert set(rm.requests.values()) == set(requests)


def test_scan_invalid(reqmanager):
    os.makedirs(str(reqmanager.requestsdir / "emptydir"))
    open(str(reqmanager.requestsdir / "foo"), "w").close()
    reqmanager.scan()  # should not raise
    assert True


def test_dont_add_ineffective_req(reqmanager):
    with reqmanager as rm:
        activity = Activity()
        activity.is_effective = False
        assert rm.add(Request(activity, 1, "comment 1")) is None
        assert not rm.requests


def test_do_add_ineffective_req_with_add_always(reqmanager):
    with reqmanager as rm:
        activity = Activity()
        activity.is_effective = False
        assert (
            rm.add(Request(activity, 1, "comment 1"), add_always=True)
            is not None
        )
        assert len(rm.requests) == 1


def test_add_dont_add_none(log, reqmanager):
    with reqmanager as rm:
        rm.add(None)


@pytest.mark.parametrize("significant", [False, True])
@unittest.mock.patch("fc.util.directory.connect")
def test_add_do_merge_compatible_request(connect, significant, log, reqmanager):
    with reqmanager as rm:
        first_activity = MergeableActivity("first")
        second_activity = MergeableActivity("second", significant)
        to_be_merged_activity = MergeableActivity("to be merged")
        first_request = Request(first_activity)
        second_request = Request(second_activity)
        to_be_merged_request = Request(to_be_merged_activity)
        assert rm.add(first_request) is first_request
        # Should not be merged because of add_always
        assert rm.add(second_request, add_always=True) is second_request
        # Should be merged
        assert rm.add(to_be_merged_request) is second_request
        assert log.has(
            "requestmanager-merge-significant"
            if significant
            else "requestmanager-merge-update",
            request=to_be_merged_request.id,
            merged=second_request.id,
        )
        assert len(rm.requests) == 2


def test_add_should_remove_no_op_request(reqmanager):
    with reqmanager as rm:
        first_activity = MergeableActivity("first")
        second_activity = MergeableActivity("inverse")
        first_request = Request(first_activity)
        second_request = Request(second_activity)
        assert rm.add(first_request) is first_request
        assert rm.add(second_request) is None
        assert len(rm.requests) == 1


def test_add_do_not_merge_incompatible_request(reqmanager):
    with reqmanager as rm:
        first_activity = MergeableActivity("first")
        second_activity = Activity()
        first_request = Request(first_activity)
        second_request = Request(second_activity)
        assert rm.add(first_request) is first_request
        assert rm.add(second_request) is second_request
        assert len(rm.requests) == 2


def test_list_other_requests(reqmanager):
    with reqmanager as rm:
        first = rm.add(Request(Activity(), 1))
        second = rm.add(Request(Activity(), 1))
        assert first.other_requests() == [second]


@unittest.mock.patch("fc.util.directory.connect")
def test_schedule_requests(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 320, "comment"))
    rpccall = connect().schedule_maintenance
    rpccall.return_value = {req.id: {"time": "2016-04-20T15:12:40.9+00:00"}}
    reqmanager.schedule()
    #
    rpccall.assert_called_once_with(
        {req.id: {"estimate": 900, "comment": "comment"}}
    )
    assert req.next_due == datetime.datetime(
        2016, 4, 20, 15, 12, 40, 900000, tzinfo=pytz.UTC
    )


@unittest.mock.patch("fc.util.directory.connect")
def test_delete_disappeared_requests(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 1, "comment"))
    sched = connect().schedule_maintenance
    sched.return_value = {
        req.id: {"time": "2016-04-20T15:12:40.9+00:00"},
        "123abc": {"time": None},
    }
    endm = connect().end_maintenance
    reqmanager.schedule()
    endm.assert_called_once_with({"123abc": {"result": "deleted"}})


@unittest.mock.patch("fc.util.directory.connect")
def test_explicitly_deleted(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 90))
    req.state = State.deleted
    end_maintenance = connect().end_maintenance
    reqmanager.archive()
    end_maintenance.assert_called_once_with(
        {
            req.id: {
                "duration": None,
                "result": "deleted",
                "comment": req.comment,
                "estimate": 900,
            }
        }
    )


@freezegun.freeze_time("2016-04-20 11:00:00")
def test_enter_maintenance(log, reqmanager, monkeypatch):
    monkeypatch.setattr(
        "fc.util.directory.connect", connect_mock := MagicMock()
    )
    monkeypatch.setattr("socket.gethostname", lambda: "host")

    reqmanager.enter_maintenance()

    assert log.has("enter-maintenance")
    connect_mock().mark_node_service_status.assert_called_with("host", False)
    maintenance_entered_at = reqmanager.maintenance_marker_path.read_text()
    assert maintenance_entered_at == "2016-04-20T11:00:00+00:00"


def test_enter_maintenance_postpone(log, reqmanager, monkeypatch):
    monkeypatch.setattr(
        "fc.util.directory.connect", connect_mock := MagicMock()
    )
    # monkeypatch.setattr("subprocess.run", run_mock := MagicMock())
    reqmanager.config["maintenance-enter"]["postpone"] = "exit 69"

    with pytest.raises(PostponeMaintenance):
        reqmanager.enter_maintenance()

    assert reqmanager.maintenance_marker_path.exists()


def test_enter_maintenance_tempfail(log, reqmanager, monkeypatch):
    monkeypatch.setattr(
        "fc.util.directory.connect", connect_mock := MagicMock()
    )
    # monkeypatch.setattr("subprocess.run", run_mock := MagicMock())
    reqmanager.config["maintenance-enter"]["tempfail"] = "exit 75"

    with pytest.raises(TempfailMaintenance):
        reqmanager.enter_maintenance()

    assert reqmanager.maintenance_marker_path.exists()


def test_execute_postpone(log, reqmanager, monkeypatch):
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    req.execute = Mock()

    def enter_maintenance_postpone():
        raise PostponeMaintenance()

    reqmanager.runnable = lambda run_all_now, force_run: [req]
    reqmanager.enter_maintenance = enter_maintenance_postpone
    reqmanager.leave_maintenance = Mock()
    reqmanager.execute()

    assert req.state == State.postpone
    assert not req.execute.called
    reqmanager.leave_maintenance.assert_called()


def test_execute_tempfail(log, reqmanager, monkeypatch):
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    req.execute = Mock()

    def enter_maintenance_tempfail():
        raise TempfailMaintenance()

    reqmanager.runnable = lambda run_all_now, force_run: [req]
    reqmanager.enter_maintenance = enter_maintenance_tempfail
    reqmanager.leave_maintenance = MagicMock()
    reqmanager.execute()

    assert req.state == State.due
    assert not req.execute.called
    reqmanager.leave_maintenance.assert_not_called()


@unittest.mock.patch("subprocess.run")
@unittest.mock.patch("fc.util.directory.connect")
def test_execute_activity_no_reboot(connect, run, reqmanager, log):
    req = reqmanager.add(Request(Activity(), 1))
    reqmanager.runnable = lambda run_all_now, force_run: [req]
    reqmanager.execute()
    run.assert_has_calls(
        [
            call('echo "entering demo"', shell=True, check=True),
            call('echo "leaving demo"', shell=True, check=True),
        ]
    )
    assert log.has("enter-maintenance")
    assert log.has("leave-maintenance")


@unittest.mock.patch("subprocess.run")
@unittest.mock.patch("fc.util.directory.connect")
@unittest.mock.patch("time.sleep")
def test_execute_activity_with_reboot(
    sleep: Mock, connect, run: Mock, reqmanager, log
):
    activity = Activity()
    activity.reboot_needed = RebootType.WARM
    req = reqmanager.add(Request(activity, 1))
    req.state = State.due
    with pytest.raises(SystemExit) as e:
        reqmanager.execute(run_all_now=True)

    assert e.value.code == 0

    run.assert_has_calls(
        [
            call('echo "entering demo"', shell=True, check=True),
            call("reboot", check=True, capture_output=True, text=True),
        ]
    )

    sleep.assert_called_once_with(5)

    assert log.has("enter-maintenance")
    assert log.has("maintenance-reboot")
    assert not log.has("leave-maintenance")


@unittest.mock.patch("subprocess.run")
@unittest.mock.patch("time.sleep")
def test_reboot_cold_reboot_has_precedence(sleep, run, reqmanager, log):
    with pytest.raises(SystemExit):
        reqmanager.reboot_and_exit({RebootType.COLD, RebootType.WARM})

    sleep.assert_called_once_with(5)
    assert log.has("maintenance-poweroff")


# XXX: Freezegun breaks if tests that don't use it run after tests that use it.
# Looks like: https://github.com/spulec/freezegun/issues/324
# Freezegun tests start here.


class PostponeActivity(Activity):
    def run(self):
        self.returncode = EXIT_POSTPONE


@freezegun.freeze_time("2016-04-20 12:00:00")
@unittest.mock.patch("fc.util.directory.connect")
def test_schedule_run_end_to_end(connect, request_population):
    import yaml
    from freezegun.api import FakeDatetime

    def yaml_represent_fake_datetime(dumper, data):
        return dumper.represent_datetime(data)

    yaml.add_representer(FakeDatetime, yaml_represent_fake_datetime)

    with request_population(3) as (rm, reqs):
        # 0: due, exec, archive
        # 1: due, exec, postpone
        reqs[1].activity = PostponeActivity()
        reqs[1].save()
        # 2, config_file=config_file: not due
        # 3: locally deleted, no req object available
    sched = connect().schedule_maintenance
    endm = connect().end_maintenance
    postp = connect().postpone_maintenance
    sched.return_value = {
        reqs[0].id: {"time": "2016-04-20T11:58:00.0+00:00"},
        reqs[1].id: {"time": "2016-04-20T11:59:00.0+00:00"},
        reqs[2].id: {"time": "2016-04-20T12:01:00.0+00:00"},
        "deleted_req": {},
    }
    with rm:
        rm.schedule()
        rm.execute()
        rm.postpone()
        rm.archive()

    endm.assert_has_calls(
        [
            call(
                {
                    "deleted_req": {
                        "result": "deleted",
                    }
                }
            ),
            call(
                {
                    "2222222222222222222222": {
                        "duration": 0.0,
                        "result": "success",
                        "comment": "0",
                        "estimate": 900,
                    }
                }
            ),
        ]
    ), "unexpected end maintenance calls"
    assert postp.call_count == 1, "unexpected postpone call count"


@freezegun.freeze_time("2016-04-20 12:00:00")
def test_update_states_continuous_requests(request_population):
    with request_population(4) as (rm, reqs):
        reqs[0].state = State.due
        reqs[0]._estimate = Estimate("20m")
        reqs[1].state = State.pending
        reqs[2].state = State.pending
        reqs[3].state = State.pending
        # The times are not ordered on purpose, update_states should sort it.
        reqs[0].next_due = datetime.datetime(
            2016, 4, 20, 12, 00, tzinfo=pytz.UTC
        )
        reqs[2].next_due = datetime.datetime(
            2016, 4, 20, 12, 20, tzinfo=pytz.UTC
        )
        reqs[1].next_due = datetime.datetime(
            2016, 4, 20, 12, 35, tzinfo=pytz.UTC
        )
        reqs[3].next_due = datetime.datetime(
            2016, 4, 20, 12, 52, tzinfo=pytz.UTC
        )
        rm.update_states()

        # Was already due, should not change
        assert reqs[0].state == State.due
        # next_due 20 minutes after the previous one with 20min estimate
        assert reqs[2].state == State.due
        # next_due 15 minutes after the previous one with 10min estimate
        assert reqs[1].state == State.due
        # next_due 17 minutes after last request, outside 16min window
        assert reqs[3].state == State.pending


@unittest.mock.patch("fc.util.directory.connect")
@freezegun.freeze_time("2016-04-20 12:00:00")
def test_execute_all_due(connect, request_population):
    with request_population(2) as (rm, reqs):
        reqs[0].state = State.due
        reqs[1].state = State.due
        reqs[0].next_due = datetime.datetime(
            2016, 4, 20, 11, 50, tzinfo=pytz.UTC
        )
        reqs[1].next_due = datetime.datetime(
            2016, 4, 20, 11, 55, tzinfo=pytz.UTC
        )
        rm.execute()
        for r in reqs:
            assert (
                len(r.attempts) == 1
            ), f"Wrong number of attempts for request {r.id}, expected exactly one"


@unittest.mock.patch("fc.util.directory.connect")
@freezegun.freeze_time("2016-04-20 12:00:00")
def test_execute_not_due(connect, request_population):
    with request_population(3) as (rm, reqs):
        reqs[0].state = State.error
        reqs[1].state = State.postpone
        reqs[2].next_due = datetime.datetime(2016, 4, 20, 13, tzinfo=pytz.UTC)
        rm.execute()
        for r in reqs:
            assert len(r.attempts) == 0


@unittest.mock.patch("fc.util.directory.connect")
def test_execute_logs_exception(connect, reqmanager, log):
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    os.chmod(req.dir, 0o000)  # simulates I/O error
    reqmanager.execute()
    log.has(
        "execute-request-failed", request=req.id, level="error", exc_info=True
    )
    os.chmod(req.dir, 0o755)  # py.test cannot clean up 0o000 dirs


@unittest.mock.patch("fc.util.directory.connect")
def test_execute_marks_service_status(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 1))
    reqmanager.execute(run_all_now=True)
    assert [
        unittest.mock.call(unittest.mock.ANY, False),
        unittest.mock.call(unittest.mock.ANY, True),
    ] == connect().mark_node_service_status.call_args_list


@unittest.mock.patch("fc.util.directory.connect")
@unittest.mock.patch("fc.maintenance.request.Request.execute")
def test_execute_not_performed_on_connection_error(
    execute, connect, reqmanager
):
    connect().mark_node_service_status.side_effect = socket.error()
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    with pytest.raises(OSError):
        reqmanager.execute()
    assert execute.mock_calls == []


@unittest.mock.patch("fc.util.directory.connect")
def test_postpone(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 90))
    req.state = State.postpone
    postp = connect().postpone_maintenance
    reqmanager.postpone()
    postp.assert_called_once_with({req.id: {"postpone_by": 180}})
    assert req.state == State.pending
    assert req.next_due is None


@unittest.mock.patch("fc.util.directory.connect")
def test_archive(connect, request_population):
    endm = connect().end_maintenance
    with request_population(5) as (rm, reqs):
        # len(ARCHIVE) == 4, won't touch the last one in reqs
        for req, state in zip(reqs, sorted(ARCHIVE)):
            req.state = state
            req._reqid = str(state)
            att = Attempt()
            att.duration = 5
            req.attempts = [att]
            req.save()
        rm.archive()
        endm.assert_called_once_with(
            {
                "deleted": {
                    "duration": 5,
                    "result": "deleted",
                    "comment": "0",
                    "estimate": 900,
                },
                "error": {
                    "duration": 5,
                    "result": "error",
                    "comment": "1",
                    "estimate": 900,
                },
                "success": {
                    "duration": 5,
                    "result": "success",
                    "comment": "2",
                    "estimate": 900,
                },
            }
        )
        for r in reqs[0:3]:
            assert "archive/" in r.dir
        assert "requests/" in reqs[4].dir


@freezegun.freeze_time("2016-04-20 11:00:00")
def test_delete(request_population):
    with request_population(1) as (rm, reqs):
        req = reqs[0]
        rm.delete(req.id)
        assert req.state == State.deleted


def test_list_empty(reqmanager):
    console = Console(file=StringIO())
    console.print(reqmanager)
    str_output = console.file.getvalue()
    assert "No maintenance requests at the moment.\n" == str_output


@freezegun.freeze_time("2016-04-20 11:00:00")
def test_list(reqmanager):
    r1 = Request(Activity(), "14m", "pending request")
    reqmanager.add(r1)
    r2 = Request(Activity(), "2h", "due request")
    r2.state = State.due
    r2.next_due = datetime.datetime(2016, 4, 20, 12, tzinfo=pytz.UTC)
    reqmanager.add(r2)
    r3 = Request(Activity(), "1m 30s", "error request")
    r3.state = State.error
    r3.next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
    att = Attempt()
    att.duration = datetime.timedelta(seconds=75)
    att.returncode = 1
    r3.attempts = [att]
    reqmanager.add(r3)
    console = Console(file=StringIO())
    console.print(reqmanager)
    str_output = console.file.getvalue()
    id1 = r1.id[:7]
    id2 = r2.id[:7]
    id3 = r3.id[:7]
    assert id1[:6] in str_output
    assert id2[:6] in str_output
    assert id3[:6] in str_output


@freezegun.freeze_time("2016-04-20 11:00:00")
def test_overdue(request_population):
    with request_population(2) as (rm, reqs):
        reqs[0].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[0].state = State.due
        reqs[1].next_due = datetime.datetime(2016, 4, 20, 10, tzinfo=pytz.UTC)
        reqs[1].state = State.due
        rm.update_states()

    assert reqs[0].state == State.due
    assert reqs[1].state == State.postpone


def test_check_no_maintenance_should_be_ok(reqmanager):
    res = reqmanager.check()
    print(res)
    assert not res.warnings
    assert not res.errors
    assert res.ok_info
    assert "Machine is in service" in res.ok_info[0]


def test_check_scheduled_requests_should_show_count_and_time(
    request_population,
):
    with request_population(2) as (rm, reqs):
        reqs[0].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[0].state = State.due
        reqs[1].next_due = datetime.datetime(
            2016, 4, 20, 11, 10, tzinfo=pytz.UTC
        )
        reqs[1].state = State.due
    res = rm.check()
    assert "2 scheduled" in res.ok_info[1]
    assert "2016-04-20 11:00" in res.ok_info[1]


def test_check_waiting_to_be_scheduled_requests_should_show_count(
    request_population,
):
    with request_population(2) as (rm, reqs):
        reqs[0].state = State.pending
        reqs[1].state = State.pending
    res = rm.check()
    assert res.ok_info
    assert "2 maintenance requests are waiting to be sched" in res.ok_info[1]


def test_check_waiting_and_scheduled_requests(
    request_population,
):
    with request_population(2) as (rm, reqs):
        reqs[0].state = State.pending
        reqs[0].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[1].state = State.pending
    res = rm.check()
    assert res.ok_info
    assert "A maintenance request is due at 2016-04-20 11:00" in res.ok_info[1]
    assert "A maintenance request is waiting to be sched" in res.ok_info[2]


@freezegun.freeze_time("2016-04-20 11:01:00")
def test_check_recent_maintenance_running_should_be_ok(request_population):
    with request_population(1) as (rm, reqs):
        rm: ReqManager
        rm.maintenance_marker_path.write_text(
            (utcnow() - datetime.timedelta(minutes=10)).isoformat()
        )
        reqs[0].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[0].state = State.running
        att = Attempt()
        att.started -= datetime.timedelta(minutes=1)
        reqs[0].attempts = [att]
        reqs[0].save()

        res = rm.check()
        print(res)
        assert not res.warnings
        assert not res.errors
        assert res.ok_info
        assert "activated 600 seconds ago" in res.ok_info[0]
        assert "request started 60 seconds ago" in res.ok_info[1]


@freezegun.freeze_time("2016-04-20 12:00:01")
def test_check_long_maintenance_should_be_critical(request_population):
    with request_population(1) as (rm, reqs):
        rm: ReqManager
        rm.maintenance_marker_path.write_text(
            (utcnow() - datetime.timedelta(minutes=60, seconds=1)).isoformat()
        )
        reqs[0].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[0].state = State.running
        att = Attempt()
        att.started -= datetime.timedelta(minutes=50)
        reqs[0].attempts = [att]
        reqs[0].save()

        res = rm.check()
        print(res)
        assert res.errors
        assert "activated 3601 seconds ago" in res.errors[0]
        assert "request started 3000 seconds ago" in res.errors[1]


@freezegun.freeze_time("2016-04-27 11:00:01")
def test_check_request_stuck_in_queue_should_warn(request_population):
    with request_population(1) as (rm, reqs):
        reqs[0].added_at = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        reqs[0].state = State.pending
        reqs[0].save()

        res = rm.check()
        print(res)
        assert res.warnings
        assert "in the queue for 168 hours" in res.warnings[0]
