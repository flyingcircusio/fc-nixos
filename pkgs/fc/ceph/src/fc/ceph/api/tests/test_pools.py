import time

import pkg_resources
import pytest

from ..cluster import Cluster
from ..pools import Pool, Pools
from ..rbdimage import RBDImage


@pytest.fixture
def cluster():
    return Cluster(
        pkg_resources.resource_filename(__name__, "fixtures/ceph.conf")
    )


@pytest.fixture
def pools(cluster, monkeypatch):
    monkeypatch.setattr(
        Pool,
        "_rbd_query",
        lambda self: """\
[{"image":"test04.root","size":21474836480,"format":1},
 {"image":"test04.tmp","size":5368709120,"format":2,"lock_type":"exclusive"}]
""",
    )
    return Pools(cluster)


class TestPools(object):
    def test_lookup_creates_pool(self, pools):
        assert isinstance(pools["test"], Pool)

    def test_lookup_caches_pool(self, pools):
        assert pools["project"] is pools["project"]

    def test_image_exists(self, pools):
        assert pools.image_exists("test", "test04.root")
        assert not pools.image_exists("foo", "bar")

    def test_pool_names(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '[{"poolnum":0,"poolname":"data"},{"poolnum":1,"poolname":'
                '"metadata"},{"poolnum":2,"poolname":"rbd"},{"poolnum":161,'
                '"poolname":"test"}]\n',
                "",
            ),
        )
        assert Pools(cluster).names() == set(
            ["data", "metadata", "rbd", "test"]
        )

    def test_all_pools(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '[{"poolnum":0,"poolname":"data"},'
                '{"poolnum":161,"poolname":"test"}]\n',
                "",
            ),
        )
        pools = Pools(cluster).all()
        assert set(["data", "test"]) == set(p.name for p in pools)

    def test_create_should_add_pool(self, cluster):
        self.call_args = []

        def record_call_args(args):
            self.call_args.append(args)

        setattr(cluster, "ceph_osd", record_call_args)
        Pools(cluster).create("new_pool")
        assert [["pool", "create", "new_pool", "32"]] == self.call_args

    def test_create_should_add_pool_to_names_cache(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '[{"poolnum":0,"poolname":"data"},'
                '{"poolnum":161,"poolname":"test"}]',
                "",
            ),
        )
        p = Pools(cluster)
        assert "new_pool" not in p.names()
        setattr(cluster, "ceph_osd", lambda args: ("created", ""))
        p.create("new_pool")
        assert "new_pool" in p.names()

    def test_pick(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '[{"poolnum":0,"poolname":"data"},'
                '{"poolnum":161,"poolname":"test"}]\n',
                "",
            ),
        )
        pool = Pools(cluster).pick()
        assert pool.name in ("data", "test")


class PgIncreaseBehaviour(object):
    """Models Ceph cluster behaviour for pg_num / pgp_num."""

    def __init__(self):
        self.calls = []

    def ceph_osd(self, args, accept_failure=False):
        self.calls.append(args)
        if "pg_num" in args:
            return "", ""
        if "pgp_num" in args:
            if len(self.calls) < 3:
                return ("", "retry", 11)
            return "success", "", 0
        raise NotImplementedError()


class TestPool(object):
    def test_pool_loads_images(self, pools):
        p = pools["test"]
        assert p.load() == {
            "test04.root": RBDImage("test04.root", 21474836480, 1, None),
            "test04.tmp": RBDImage("test04.tmp", 5368709120, 2, "exclusive"),
        }

    def test_lookup_caches_image(self, pools):
        p = pools["test"]
        assert p["test04.tmp"] is p["test04.tmp"]

    def test_unknown_image(self, pools):
        p = pools["test"]
        with pytest.raises(KeyError):
            p["unknown"]

    def test_unknown_pool_gives_keyerror(self, cluster):
        setattr(
            cluster,
            "rbd",
            lambda args, accept_failure, ignore_dry_run: (
                "",
                "rbd: error opening pool test2: (2) No such file or "
                "directory\n",
                2,
            ),
        )
        with pytest.raises(KeyError):
            Pool("test2", cluster)._rbd_query()

    def test_empty_pool_returns_empty_set(self, cluster):
        setattr(
            cluster,
            "rbd",
            lambda args, accept_failure, ignore_dry_run: (
                "",
                "rbd: pool t3 doesn't contain rbd images\n",
                2,
            ),
        )
        assert "[]" == Pool("t3", cluster)._rbd_query()

    def test_get_pg_num(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '{"pool":"test","pool_id":161,"pg_num":512}',
                "",
            ),
        )
        assert 512 == Pool("test", cluster).pg_num

    def test_set_pg_num(self, cluster, monkeypatch):
        behaviour_model = PgIncreaseBehaviour()
        setattr(cluster, "ceph_osd", behaviour_model.ceph_osd)
        monkeypatch.setattr(time, "sleep", lambda t: None)
        p = Pool("test", cluster)
        p.pg_num = 32
        assert p.pg_num == 32
        assert p.pgp_num == 32
        assert behaviour_model.calls == [
            ["pool", "set", "test", "pg_num", "32"],
            ["pool", "set", "test", "pgp_num", "32"],
            ["pool", "set", "test", "pgp_num", "32"],
        ]

    def test_get_pgp_num(self, cluster):
        setattr(
            cluster,
            "ceph_osd",
            lambda args, ignore_dry_run: (
                '{"pool":"test","pool_id":161,"pgp_num":128}',
                "",
            ),
        )
        assert 128 == Pool("test", cluster).pgp_num

    def test_set_pgp_num_failure(self, cluster, monkeypatch):
        setattr(
            cluster, "ceph_osd", lambda args, accept_failure: ("", "failed", 1)
        )
        monkeypatch.setattr(time, "sleep", lambda t: None)
        with pytest.raises(RuntimeError):
            Pool("test", cluster).pgp_num = 100

    def test_total_size(self, pools):
        assert 25 == pools["test"].size_total_gb

    def test_total_size_should_exclude_snapshots(self, cluster, monkeypatch):
        monkeypatch.setattr(
            Pool,
            "_rbd_query",
            lambda self: """\
[{"image":"test04.root","size":21474836480,"format":1},
 {"format":2,"image":"test03.root","size":10737418240,"protected":"false",\
  "snapshot":"backy-ZEQmgR6PsqPyj6235sUBAK"},
 {"image":"test04.tmp","size":5368709120,"format":2,"lock_type":"exclusive"}]
""",
        )
        pools = Pools(cluster)
        assert 25 == pools["test"].size_total_gb
