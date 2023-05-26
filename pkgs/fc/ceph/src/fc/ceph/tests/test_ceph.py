import collections

import fc.ceph.api.cluster
import fc.ceph.maintenance
import fc.util.configfile
import fc.util.directory
import mock
import pytest
from fc.ceph.api.rbdimage import RBDImage


@pytest.fixture
def fake_directory():
    d = mock.MagicMock(spec=["deletions"])
    d.deletions.return_value = collections.OrderedDict(
        [
            ("node00", {"stages": []}),
            ("node01", {"stages": ["prepare"]}),
            ("node02", {"stages": ["prepare", "soft"]}),
            ("node03", {"stages": ["prepare", "soft", "hard"]}),
            ("node04", {"stages": ["prepare", "soft", "hard", "purge"]}),
        ]
    )
    return d


@pytest.fixture
def cluster(monkeypatch):
    monkeypatch.setattr(
        fc.ceph.api.cluster.Cluster,
        "rbd",
        mock.MagicMock(spec=fc.ceph.api.cluster.Cluster.rbd),
    )
    return fc.ceph.api.cluster.Cluster(ceph_id="admin")


@pytest.fixture
def pools(cluster, monkeypatch):
    monkeypatch.setattr(
        fc.ceph.api.pools.Pools,
        "names",
        lambda self: set(["rbd.hdd", "rbd.ssd"]),
    )
    images_hdd = {}
    images_ssd = {}
    for node in range(5):
        images = images_hdd if node % 2 else images_ssd
        name = "node0{}".format(node)
        images["{}.root".format(name)] = RBDImage("{}.root".format(name), 100)
        images["{}.root@snap1".format(name)] = RBDImage(
            "{}.root".format(name), 100, snapshot="snap1"
        )
        images["{}.swap".format(name)] = RBDImage("{}.swap".format(name), 100)
        images["{}.tmp".format(name)] = RBDImage("{}.tmp".format(name), 100)
    monkeypatch.setattr(
        fc.ceph.api.pools.Pool,
        "load",
        lambda self: images_hdd if self.name == "rbd.hdd" else images_ssd,
    )
    return fc.ceph.api.pools.Pools(cluster)


def test_node_deletion(fake_directory, cluster, pools, maintenance_manager):
    v = maintenance_manager.VolumeDeletions(fake_directory, cluster)
    v.ensure()

    assert cluster.rbd.call_args_list == [
        # hard
        mock.call(["snap", "rm", "rbd.hdd/node03.root@snap1"]),
        mock.call(["rm", "rbd.hdd/node03.root"]),
        mock.call(["rm", "rbd.hdd/node03.swap"]),
        mock.call(["rm", "rbd.hdd/node03.tmp"]),
        # purge
        mock.call(["snap", "rm", "rbd.ssd/node04.root@snap1"]),
        mock.call(["rm", "rbd.ssd/node04.root"]),
        mock.call(["rm", "rbd.ssd/node04.swap"]),
        mock.call(["rm", "rbd.ssd/node04.tmp"]),
    ]
