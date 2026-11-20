import os
from textwrap import dedent

import fc.ceph.maintenance as maintSub
import fc.ceph.util
import pytest


@pytest.fixture
def fc_ceph_conf(monkeypatch, tmp_path):
    """Point the fc-ceph/fc-luks CLI at a minimal config file.

    Needed by every test that drives an entry point in `fc.ceph.main`, as
    `Environment.prepare` exits when no config file can be read. It also
    overwrites PATH from that config, so restore PATH afterwards to keep the
    rest of the session from running with only `path` on it.
    """
    conf = tmp_path / "fc-ceph.conf"
    conf.write_text(
        dedent(
            """\
            [default]
            path=/bin
            release=pacific
            """
        )
    )
    monkeypatch.setattr("fc.ceph.main.CONFIG_FILE_PATH", conf)
    monkeypatch.setenv("PATH", os.environ["PATH"])


@pytest.fixture(params=[maintSub.nautilus])
def maintenance_manager_legacy(request):
    """returns a maintenance manager for all Ceph releases supported by fc-ceph"""
    return request.param


@pytest.fixture
def maintenance_manager():
    """returns a maintenance manager just for the latest Ceph release supported by fc-ceph"""
    return maintSub.nautilus
