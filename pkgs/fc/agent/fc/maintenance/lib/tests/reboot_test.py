from fc.maintenance.lib.reboot import RebootActivity, main
from fc.maintenance.reqmanager import ReqManager

from unittest.mock import Mock
import pytest
import sys


@pytest.fixture
def defused_boom(monkeypatch):
    mock = Mock(RebootActivity.boom)
    monkeypatch.setattr(RebootActivity, 'boom', mock)
    return mock


@pytest.fixture
def reqdir(tmpdir, monkeypatch):
    monkeypatch.chdir(tmpdir)
    return tmpdir


@pytest.fixture
def boottime(monkeypatch):
    """Simulate fixed boottime (i.e., no intermediary reboots)."""
    boottime = Mock(RebootActivity.boottime, side_effect=[1] * 20)
    monkeypatch.setattr(RebootActivity, 'boottime', boottime)
    return boottime


def test_reboot(reqdir, defused_boom, boottime):
    r = RebootActivity()
    r.run()
    assert defused_boom.call_count == 1


def test_skip_reboot_when_already_rebooted(reqdir, defused_boom, monkeypatch):
    boottime = Mock(RebootActivity.boottime, side_effect=[1, 10])
    monkeypatch.setattr(RebootActivity, 'boottime', boottime)
    r = RebootActivity()
    r.run()
    assert defused_boom.call_count == 0


def comments(spooldir):
    """Returns dict of (reqid, comment)."""
    with ReqManager(str(spooldir)) as rm:
        rm.scan()
        return [req.comment for req in rm.requests.values()]


def test_dont_perfom_warm_reboot_if_cold_reboot_pending(
        reqdir, defused_boom, boottime):
    for type_ in [[], ['--poweroff']]:
        sys.argv = [
            'reboot',
            '--spooldir={}'.format(str(reqdir)),
            '--comment={}'.format(type_),
        ] + type_
        main()

    with ReqManager(str(reqdir)) as rm:
        rm.scan()
        # run soft reboot first
        reqs = sorted(
            rm.requests.values(),
            key=lambda r: r.activity.action,
            reverse=True)
        reqs[0].execute()
        reqs[0].save()
        assert defused_boom.call_count == 0
        reqs[1].execute()
        reqs[1].save()
        assert defused_boom.call_count == 1
