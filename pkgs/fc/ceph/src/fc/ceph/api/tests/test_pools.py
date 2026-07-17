import time
from subprocess import CalledProcessError
from unittest.mock import MagicMock

from pathlib import Path
import pytest

from ..cluster import Cluster
from ..pools import Pool, Pools
from ..rbdimage import RBDImage


@pytest.fixture
def cluster():
    return Cluster(
       Path(__file__).parent / "fixtures/ceph.conf"
    )


@pytest.fixture
def pools(cluster, monkeypatch):
    monkeypatch.setattr(
        Pool,
        "_rbd_query",
        lambda self: [
            {"image": "test04.root", "size": 21474836480, "format": 1},
            {
                "image": "test04.tmp",
                "size": 5368709120,
                "format": 2,
                "lock_type": "exclusive",
            },
        ],
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

    def test_pool_names(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: [
                {"poolnum": 0, "poolname": "data"},
                {"poolnum": 1, "poolname": "metadata"},
                {"poolnum": 2, "poolname": "rbd"},
                {"poolnum": 161, "poolname": "test"},
            ],
        )
        assert Pools(cluster).names() == set(
            ["data", "metadata", "rbd", "test"]
        )

    def test_all_pools(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: [
                {"poolnum": 0, "poolname": "data"},
                {"poolnum": 161, "poolname": "test"},
            ],
        )
        pools = Pools(cluster).all()
        assert set(["data", "test"]) == set(p.name for p in pools)

    def test_create_should_add_pool(self, cluster, monkeypatch):
        call_args = []

        def record_call_args(*args):
            call_args.append(list(args))

        monkeypatch.setattr("fc.ceph.api.pools.run.ceph", record_call_args)
        Pools(cluster).create("new_pool")
        assert [
            ["-c", cluster.ceph_conf, "osd", "pool", "create", "new_pool", "32"]
        ] == call_args

    def test_create_should_add_pool_to_names_cache(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: [
                {"poolnum": 0, "poolname": "data"},
                {"poolnum": 161, "poolname": "test"},
            ],
        )
        p = Pools(cluster)
        assert "new_pool" not in p.names()
        monkeypatch.setattr("fc.ceph.api.pools.run.ceph", lambda *args: None)
        p.create("new_pool")
        assert "new_pool" in p.names()

    def test_pick(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: [
                {"poolnum": 0, "poolname": "data"},
                {"poolnum": 161, "poolname": "test"},
            ],
        )
        pool = Pools(cluster).pick()
        assert pool.name in ("data", "test")


class PgIncreaseBehaviour(object):
    """Models Ceph cluster behaviour for pg_num / pgp_num."""

    def __init__(self):
        self.calls = []

    def ceph(self, *args, **kwargs):
        self.calls.append(list(args))
        if "pg_num" in args:
            return {"pool": "test", "pg_num": 32}
        if "pgp_num" in args:
            if len(self.calls) < 3:
                raise CalledProcessError(11, "ceph", stderr="retry")
            return {"pool": "test", "pgp_num": 32}
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

    def test_unknown_pool_gives_keyerror(self, cluster, monkeypatch):
        def rbd_raise(*args, **kwargs):
            raise CalledProcessError(
                2,
                "rbd",
                output="",
                stderr="rbd: error opening pool test2: (2) No such file or "
                "directory\n",
            )

        monkeypatch.setattr("fc.ceph.api.pools.run.json.rbd", rbd_raise)
        with pytest.raises(KeyError):
            Pool("test2", cluster)._rbd_query()

    def test_empty_pool_returns_empty_set(self, cluster, monkeypatch):
        def rbd_raise(*args, **kwargs):
            raise CalledProcessError(
                2,
                "rbd",
                output="",
                stderr="rbd: pool t3 doesn't contain rbd images\n",
            )

        monkeypatch.setattr("fc.ceph.api.pools.run.json.rbd", rbd_raise)
        assert [] == Pool("t3", cluster)._rbd_query()

    def test_get_pg_num(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: {"pool": "test", "pool_id": 161, "pg_num": 512},
        )
        assert 512 == Pool("test", cluster).pg_num

    def test_set_pg_num(self, cluster, monkeypatch):
        behaviour_model = PgIncreaseBehaviour()
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph", behaviour_model.ceph
        )
        monkeypatch.setattr("fc.ceph.api.pools.run.ceph", behaviour_model.ceph)
        monkeypatch.setattr(time, "sleep", lambda t: None)
        p = Pool("test", cluster)
        p.pg_num = 32
        assert p.pg_num == 32
        assert p.pgp_num == 32
        assert behaviour_model.calls == [
            [
                "-c",
                cluster.ceph_conf,
                "osd",
                "pool",
                "set",
                "test",
                "pg_num",
                "32",
            ],
            [
                "-c",
                cluster.ceph_conf,
                "osd",
                "pool",
                "set",
                "test",
                "pgp_num",
                "32",
            ],
            [
                "-c",
                cluster.ceph_conf,
                "osd",
                "pool",
                "set",
                "test",
                "pgp_num",
                "32",
            ],
        ]

    def test_get_pg_num_min(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: {
                "pool": "test",
                "pool_id": 161,
                "pg_num": 512,
                "pg_num_min": 1,
            },
        )
        assert 1 == Pool("test", cluster).pg_num_min

        def raiser(*args):
            raise CalledProcessError(
                returncode=2,
                cmd="ceph -c /etc/ceph/ceph.conf osd pool get test1 pg_num_min",
                stderr=b"Error ENOENT: option 'pg_num_min' is not set on pool 'test1'",
            )

        monkeypatch.setattr("fc.ceph.api.pools.run.json.ceph", raiser)
        assert Pool("test1", cluster).pg_num_min is None

    def test_set_pg_num_min(self, cluster, monkeypatch):
        mock_ceph = MagicMock()
        monkeypatch.setattr("fc.ceph.api.pools.run.ceph", mock_ceph)

        p = Pool("test", cluster)
        p.pg_num_min = 1
        mock_ceph.assert_called_with(
            "-c",
            cluster.ceph_conf,
            "osd",
            "pool",
            "set",
            "test",
            "pg_num_min",
            "1",
        )
        assert p._pg_num_min == 1

        mock_ceph.reset_mock()
        p.pg_num_min = None
        mock_ceph.assert_called_with(
            "-c",
            cluster.ceph_conf,
            "osd",
            "pool",
            "set",
            "test",
            "pg_num_min",
            "0",
        )
        assert p._pg_num_min is None

    def test_get_pgp_num(self, cluster, monkeypatch):
        monkeypatch.setattr(
            "fc.ceph.api.pools.run.json.ceph",
            lambda *args: {"pool": "test", "pool_id": 161, "pgp_num": 128},
        )
        assert 128 == Pool("test", cluster).pgp_num

    def test_set_pgp_num_failure(self, cluster, monkeypatch):
        def ceph_raise(*args, **kwargs):
            raise CalledProcessError(1, "ceph", stderr="failed")

        monkeypatch.setattr("fc.ceph.api.pools.run.ceph", ceph_raise)
        monkeypatch.setattr(time, "sleep", lambda t: None)
        with pytest.raises(RuntimeError):
            Pool("test", cluster).pgp_num = 100

    def test_total_size(self, pools):
        assert 25 == pools["test"].size_total_gb

    def test_total_size_should_exclude_snapshots(self, cluster, monkeypatch):
        monkeypatch.setattr(
            Pool,
            "_rbd_query",
            lambda self: [
                {"image": "test04.root", "size": 21474836480, "format": 1},
                {
                    "format": 2,
                    "image": "test03.root",
                    "size": 10737418240,
                    "protected": "false",
                    "snapshot": "backy-ZEQmgR6PsqPyj6235sUBAK",
                },
                {
                    "image": "test04.tmp",
                    "size": 5368709120,
                    "format": 2,
                    "lock_type": "exclusive",
                },
            ],
        )
        pools = Pools(cluster)
        assert 25 == pools["test"].size_total_gb
