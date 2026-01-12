import json
from copy import deepcopy
from unittest import mock

import fc.check_ceph.check_snapshot_restore as snapcheck
import pytest


@pytest.fixture
def rbd_pool_images():
    """RBD pool images - what images exist in each pool"""
    return {
        "rbd.hdd": ["test01", "testdeleted", "test02"],
        "rbd.ssd": ["test03"],
        "emptypool": [],
    }


@pytest.fixture
def rbd_snapshot_data():
    """RBD snapshot data - what snapshots exist for each image"""
    return {
        "rbd.hdd/test01": [
            {"name": "zerosnap", "size": 0},
            {"name": "backy-2342", "size": 2345678},
        ],
        "rbd.hdd/test02": [],
        "rbd.ssd/test03": [{"name": "footest", "size": 1024}],
    }


@pytest.fixture
def example_thresholds():
    return snapcheck.Thresholds(0.85, 0.95)


@pytest.fixture
def snapshot(example_thresholds):
    thresh = example_thresholds
    default_root = snapcheck.CrushRoot("default", 0, 0, thresh)
    rbd_hdd = snapcheck.Pool("rbd.hdd", default_root)
    snap = snapcheck.Snapshot(rbd_hdd, "test01", "backy-1337", 0)
    return snap


@pytest.fixture
def snap_ok(snapshot):
    snapshot = deepcopy(snapshot)
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.used = 2000
    snapshot.size = 1000

    return snapshot


@pytest.fixture
def snap_warn(snapshot):
    snapshot = deepcopy(snapshot)
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.used = 2000
    snapshot.size = 850000

    return snapshot


@pytest.fixture
def snap_critical(snapshot):
    snapshot = deepcopy(snapshot)
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.used = 2000
    snapshot.size = 950000

    return snapshot


# real-world mock data
cephOsdDfTreeOutput = json.dumps(
    {
        "nodes": [
            {
                "id": -10,
                "name": "ssd",
                "type": "root",
                "type_id": 6,
                "reweight": -1,
                # sizes have been manually adjusted for this test
                "kb": 107374182400,  # 100 TiB
                "kb_used": 64424509440,  # 60 TiB
                # interestingly, kb_used != sum of data, omap, meta in real-world data
                "kb_used_data": 64414023680,
                "kb_used_omap": 5242880,
                "kb_used_meta": 10485760,
                "kb_avail": 42949672960,  # 40 TiB
                "utilization": 60.00,
                "var": 0.7578097474242926,
                "pgs": 0,
                "children": [-9],
            },
            {
                "id": -1,
                "name": "default",
                "type": "root",
                "type_id": 6,
                "reweight": -1,
                "kb": 107374182400,  # 100 TiB
                "kb_used": 64424509440,  # 60 TiB
                "kb_used_data": 64414023680,
                "kb_used_omap": 5242880,
                "kb_used_meta": 10485760,
                "kb_avail": 42949672960,  # 40 TiB
                "utilization": 60.00,
                "var": 1.1818457571571093,
                "pgs": 0,
                "children": [-2],
            },
            # also include a non-crush-root node type
            {
                "id": 10,
                "device_class": "ssd",
                "name": "osd.10",
                "type": "osd",
                "type_id": 0,
                "crush_weight": 1.7446136474609375,
                "depth": 4,
                "pool_weights": {},
                "reweight": 1,
                "kb": 1873268736,
                "kb_used": 686339104,
                "kb_used_data": 684799892,
                "kb_used_omap": 14187,
                "kb_used_meta": 2022228,
                "kb_avail": 1186929632,
                "utilization": 36.638582111050617,
                "var": 1.0741663732843056,
                "pgs": 257,
                "status": "up",
            },
        ]
    }
)


# already prepare possibility of testing with different ceph release outputs
@pytest.fixture(params=[cephOsdDfTreeOutput])
def ceph_osd_df_tree_json(request) -> str:
    return request.param


@pytest.fixture
def parsed_raw_cluster_fillstats(ceph_osd_df_tree_json, monkeypatch):
    """returns the still almost raw, but only slightly pre-processed ceph cluster
    fill stats as input for further parsing"""
    # Mock subprocess.run to return the test data
    mock_result = mock.Mock()
    mock_result.stdout = ceph_osd_df_tree_json
    monkeypatch.setattr(
        "fc.check_ceph.check_snapshot_restore.subprocess.run",
        mock.Mock(return_value=mock_result),
    )
    return snapcheck._ceph_osd_df_tree_roots()


@pytest.fixture
def default_pool_roots():
    return {
        "default": ["rbd.hdd"],
        "ssd": ["rbd.ssd"],
    }
