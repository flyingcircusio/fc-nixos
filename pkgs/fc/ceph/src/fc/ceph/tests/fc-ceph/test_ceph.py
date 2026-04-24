import collections

import fc.ceph.api.cluster
import fc.ceph.api.pools
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
def mock_rbd(monkeypatch):
    mock_rbd = mock.MagicMock()
    monkeypatch.setattr("fc.ceph.api.pools.run.json.rbd", mock_rbd)
    monkeypatch.setattr("fc.ceph.api.pools.run.rbd", mock_rbd)
    return mock_rbd


@pytest.fixture
def cluster():
    return fc.ceph.api.cluster.Cluster()


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


def test_node_deletion(
    fake_directory, cluster, pools, maintenance_manager, mock_rbd
):
    v = maintenance_manager.VolumeDeletions(fake_directory, cluster)
    v.ensure()

    assert mock_rbd.call_args_list == [
        # hard
        mock.call(
            "-c",
            "/etc/ceph/ceph.conf",
            "snap",
            "rm",
            "rbd.hdd/node03.root@snap1",
        ),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.hdd/node03.root"),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.hdd/node03.swap"),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.hdd/node03.tmp"),
        # purge
        mock.call(
            "-c",
            "/etc/ceph/ceph.conf",
            "snap",
            "rm",
            "rbd.ssd/node04.root@snap1",
        ),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.ssd/node04.root"),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.ssd/node04.swap"),
        mock.call("-c", "/etc/ceph/ceph.conf", "rm", "rbd.ssd/node04.tmp"),
    ]
