import contextlib
import datetime
import os
import os.path as p
import socket
import sys
import textwrap
import unittest.mock
import uuid
from unittest.mock import call

import fc.maintenance.reqmanager
import freezegun
import pytest
import pytz
import shortuuid
from fc.maintenance.activity import Activity, RebootType
from fc.maintenance.reqmanager import ReqManager
from fc.maintenance.request import Attempt, Request
from fc.maintenance.state import ARCHIVE, EXIT_POSTPONE, State


@pytest.fixture
def agent_maintenance_config(tmpdir):
    config_file = str(tmpdir / 'fc-agent.conf')
    with open(config_file, 'w') as f:
        f.write(
            textwrap.dedent("""\
            [maintenance-enter]
            demo = echo "entering demo"

            [maintenance-leave]
            demo = echo "leaving demo"
            dummy =
            """))
    return config_file


@pytest.fixture
def reqmanager(tmpdir, agent_maintenance_config):
    with ReqManager(str(tmpdir), config_file=agent_maintenance_config) as rm:
        yield rm


@contextlib.contextmanager
def request_population(n, dir, config_file=None):
    """Creates a ReqManager with a pregenerated population of N requests.

    The ReqManager and a list of Requests are passed to the calling code.
    """
    with ReqManager(str(dir), config_file=config_file) as reqmanager:
        requests = []
        for i in range(n):
            req = Request(Activity(), 60, comment=str(i))
            req._reqid = shortuuid.encode(uuid.UUID(int=i))
            reqmanager.add(req)
            requests.append(req)
        yield (reqmanager, requests)


def test_init_should_create_directories(tmpdir):
    spooldir = str(tmpdir / 'maintenance')
    ReqManager(spooldir)
    assert p.isdir(spooldir)
    assert p.isdir(p.join(spooldir, 'requests'))
    assert p.isdir(p.join(spooldir, 'archive'))


def test_lockfile(tmpdir):
    with ReqManager(str(tmpdir)):
        with open(str(tmpdir / '.lock')) as f:
            assert f.read().strip() == str(os.getpid())
    with open(str(tmpdir / '.lock')) as f:
        assert f.read() == ''


def test_req_save(tmpdir):
    with request_population(1, tmpdir) as (rm, requests):
        req = requests[0]
        assert p.isfile(p.join(req.dir, 'request.yaml'))
        print(open(p.join(req.dir, 'request.yaml')).read())


class FunnyActivity(Activity):

    def __init__(self, mood):
        self.mood = mood


def test_scan(tmpdir):
    with request_population(3, tmpdir) as (rm, requests):
        requests[0].comment = 'foo'
        requests[0].save()
        requests[1].activity = FunnyActivity('good')
        requests[1].save()
    with ReqManager(str(tmpdir)) as rm:
        assert set(rm.requests.values()) == set(requests)


def test_scan_invalid(tmpdir):
    os.makedirs(str(tmpdir / 'requests' / 'emptydir'))
    open(str(tmpdir / 'requests' / 'foo'), 'w').close()
    ReqManager(str(tmpdir)).scan()  # should not raise
    assert True


def test_find_by_comment(reqmanager):
    with reqmanager as rm:
        rm.add(Request(Activity(), 1, 'comment 1'))
        req2 = rm.add(Request(Activity(), 1, 'comment 2'))
    with reqmanager as rm:
        assert req2 == rm.find_by_comment('comment 2')


def test_find_by_comment_returns_none_on_mismatch(reqmanager):
    with reqmanager as rm:
        assert rm.find_by_comment('no such comment') is None


def test_dont_add_two_reqs_with_identical_comments(reqmanager):
    with reqmanager as rm:
        assert rm.add(Request(Activity(), 1, 'comment 1')) is not None
        assert rm.add(Request(Activity(), 1, 'comment 1')) is None
        assert len(rm.requests) == 1


def test_do_add_two_reqs_with_identical_comments(reqmanager):
    with reqmanager as rm:
        assert rm.add(Request(Activity(), 1, 'comment 1')) is not None
        assert rm.add(
            Request(Activity(), 1, 'comment 1'),
            skip_same_comment=False) is not None
        assert len(rm.requests) == 2


def test_list_other_requests(reqmanager):
    with reqmanager as rm:
        first = rm.add(Request(Activity(), 1))
        second = rm.add(Request(Activity(), 1))
        assert first.other_requests() == [second]


@unittest.mock.patch('fc.util.directory.connect')
def test_schedule_requests(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 1, 'comment'))
    rpccall = connect().schedule_maintenance
    rpccall.return_value = {req.id: {'time': '2016-04-20T15:12:40.9+00:00'}}
    reqmanager.schedule()
    rpccall.assert_called_once_with(
        {req.id: {
            'estimate': 1,
            'comment': 'comment'
        }})
    assert req.next_due == datetime.datetime(
        2016, 4, 20, 15, 12, 40, 900000, tzinfo=pytz.UTC)


@unittest.mock.patch('fc.util.directory.connect')
def test_delete_disappeared_requests(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 1, 'comment'))
    sched = connect().schedule_maintenance
    sched.return_value = {
        req.id: {
            'time': '2016-04-20T15:12:40.9+00:00'
        },
        '123abc': {
            'time': None
        },
    }
    endm = connect().end_maintenance
    reqmanager.schedule()
    endm.assert_called_once_with({'123abc': {'result': 'deleted'}})


@unittest.mock.patch('fc.util.directory.connect')
def test_explicitly_deleted(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 90))
    req.state = State.deleted
    arch = connect().end_maintenance
    reqmanager.archive()
    arch.assert_called_once_with(
        {req.id: {
            'duration': None,
            'result': 'deleted'
        }})


@unittest.mock.patch('subprocess.run')
@unittest.mock.patch('fc.util.directory.connect')
def test_execute_activity_no_reboot(connect, run, reqmanager, log):
    activity = Activity()
    req = reqmanager.add(Request(activity, 1))
    req.state = State.due
    reqmanager.execute(run_all_now=True)
    run.assert_has_calls([
        call('echo "entering demo"', shell=True, check=True),
        call('echo "leaving demo"', shell=True, check=True)
    ])
    assert log.has("enter-maintenance")
    assert log.has("leave-maintenance")


@unittest.mock.patch('subprocess.run')
@unittest.mock.patch('fc.util.directory.connect')
def test_execute_activity_with_reboot(connect, run, reqmanager, log):
    activity = Activity()
    activity.reboot_needed = RebootType.WARM
    req = reqmanager.add(Request(activity, 1))
    req.state = State.due
    reqmanager.execute(run_all_now=True)
    run.assert_has_calls([
        call('echo "entering demo"', shell=True, check=True),
        call('reboot', check=True, capture_output=True, text=True)
    ])
    assert log.has("enter-maintenance")
    assert log.has("maintenance-reboot")
    assert not log.has("leave-maintenance")


@unittest.mock.patch('subprocess.run')
def test_reboot_cold_reboot_has_precedence(run, reqmanager, log):
    reqmanager.reboot({RebootType.COLD, RebootType.WARM})
    assert log.has("maintenance-poweroff")


# XXX: Freezegun breaks if tests that don't use it run after tests that use it.
# Looks like: https://github.com/spulec/freezegun/issues/324
# Freezegun tests start here.


@freezegun.freeze_time('2016-04-20 11:00:00')
def test_delete_end_to_end(tmpdir):
    with request_population(1, tmpdir) as (rm, reqs):
        req = reqs[0]
        rm.delete(req.id[0:7])
        assert req.state == State.deleted


@freezegun.freeze_time('2016-04-20 11:00:00')
def test_list_end_to_end(tmpdir, capsys):
    with request_population(1, tmpdir) as (rm, reqs):
        sys.argv = ['list-maintenance', '--spooldir', str(tmpdir)]
        fc.maintenance.reqmanager.list_maintenance()
        out, err = capsys.readouterr()
        assert reqs[0].id[0:7] in out


@unittest.mock.patch('fc.util.directory.connect')
@freezegun.freeze_time('2016-04-20 12:00:00')
def test_execute_all_due(connect, tmpdir, agent_maintenance_config):
    with request_population(
            3, tmpdir, config_file=agent_maintenance_config) as (rm, reqs):
        reqs[0].state = State.running
        reqs[1].state = State.tempfail
        reqs[1].next_due = datetime.datetime(2016, 4, 20, 10, tzinfo=pytz.UTC)
        reqs[2].next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
        rm.execute()
        for r in reqs:
            assert len(r.attempts) == 1


@unittest.mock.patch('fc.util.directory.connect')
@freezegun.freeze_time('2016-04-20 12:00:00')
def test_execute_not_due(connect, tmpdir, agent_maintenance_config):
    with request_population(
            3, tmpdir, config_file=agent_maintenance_config) as (rm, reqs):
        reqs[0].state = State.error
        reqs[1].state = State.postpone
        reqs[2].next_due = datetime.datetime(2016, 4, 20, 13, tzinfo=pytz.UTC)
        rm.execute()
        for r in reqs:
            assert len(r.attempts) == 0


@unittest.mock.patch('fc.util.directory.connect')
def test_execute_logs_exception(connect, reqmanager, log):
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    os.chmod(req.dir, 0o000)  # simulates I/O error
    reqmanager.execute()
    log.has(
        "execute-request-failed", request=req.id, level="error", exc_info=True)
    os.chmod(req.dir, 0o755)  # py.test cannot clean up 0o000 dirs


@unittest.mock.patch('fc.util.directory.connect')
def test_execute_marks_service_status(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    reqmanager.execute()
    assert [
        unittest.mock.call(unittest.mock.ANY, False),
        unittest.mock.call(unittest.mock.ANY, True)] == \
        connect().mark_node_service_status.call_args_list


@unittest.mock.patch('fc.util.directory.connect')
@unittest.mock.patch('fc.maintenance.request.Request.execute')
def test_execute_not_performed_on_connection_error(execute, connect,
                                                   reqmanager):
    connect().mark_node_service_status.side_effect = socket.error()
    req = reqmanager.add(Request(Activity(), 1))
    req.state = State.due
    with pytest.raises(OSError):
        reqmanager.execute()
    assert execute.mock_calls == []


@unittest.mock.patch('fc.util.directory.connect')
def test_postpone(connect, reqmanager):
    req = reqmanager.add(Request(Activity(), 90))
    req.state = State.postpone
    postp = connect().postpone_maintenance
    reqmanager.postpone()
    postp.assert_called_once_with({req.id: {'postpone_by': 180}})
    assert req.state == State.postpone
    assert req.next_due is None


@unittest.mock.patch('fc.util.directory.connect')
def test_archive(connect, tmpdir):
    endm = connect().end_maintenance
    with request_population(5, tmpdir) as (rm, reqs):
        # len(ARCHIVE) == 4, won't touch the last one in reqs
        for req, state in zip(reqs, sorted(ARCHIVE)):
            req.state = state
            req._reqid = str(state)
            att = Attempt()
            att.duration = 5
            req.attempts = [att]
            req.save()
        rm.archive()
        endm.assert_called_once_with({
            'success': {
                'duration': 5,
                'result': 'success'
            },
            'error': {
                'duration': 5,
                'result': 'error'
            },
            'retrylimit': {
                'duration': 5,
                'result': 'retrylimit'
            },
            'deleted': {
                'duration': 5,
                'result': 'deleted'
            },
        })
        for r in reqs[0:3]:
            assert 'archive/' in r.dir
        assert 'requests/' in reqs[4].dir


class PostponeActivity(Activity):

    def run(self):
        self.returncode = EXIT_POSTPONE


@freezegun.freeze_time('2016-04-20 12:00:00')
@unittest.mock.patch('fc.util.directory.connect')
def test_end_to_end(connect, tmpdir, agent_maintenance_config):
    with request_population(
            3, tmpdir, config_file=agent_maintenance_config) as (rm, reqs):
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
        reqs[0].id: {
            'time': '2016-04-20T11:58:00.0+00:00'
        },
        reqs[1].id: {
            'time': '2016-04-20T11:59:00.0+00:00'
        },
        reqs[2].id: {
            'time': '2016-04-20T12:01:00.0+00:00'
        },
        'deleted_req': {},
    }
    fc.maintenance.reqmanager.transaction(
        tmpdir, config_file=agent_maintenance_config)
    assert sched.call_count == 1
    endm.assert_has_calls([
        call({'deleted_req': {
            'result': 'deleted'
        }}),
        call(
            {'2222222222222222222222': {
                'duration': 0.0,
                'result': 'success'
            }})
    ])
    assert postp.call_count == 1


def test_list_empty(reqmanager):
    assert '' == str(reqmanager)


@freezegun.freeze_time('2016-04-20 11:00:00')
def test_list(reqmanager):
    r1 = Request(Activity(), '14m', 'pending request')
    reqmanager.add(r1)
    r2 = Request(Activity(), '2h', 'due request')
    r2.state = State.due
    r2.next_due = datetime.datetime(2016, 4, 20, 12, tzinfo=pytz.UTC)
    reqmanager.add(r2)
    r3 = Request(Activity(), '1m 30s', 'error request')
    r3.state = State.error
    r3.next_due = datetime.datetime(2016, 4, 20, 11, tzinfo=pytz.UTC)
    att = Attempt()
    att.duration = datetime.timedelta(seconds=75)
    att.returncode = 1
    r3.attempts = [att]
    reqmanager.add(r3)
    assert str(reqmanager) == """\
St Id       Scheduled             Estimate  Comment
e  {id3}  2016-04-20 11:00 UTC  1m 30s    error request (duration: 1m 15s)
*  {id2}  2016-04-20 12:00 UTC  2h        due request
-  {id1}  --- TBA ---           14m       pending request\
""".format(
        id1=r1.id[:7], id2=r2.id[:7], id3=r3.id[:7])
