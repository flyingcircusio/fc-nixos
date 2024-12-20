import json
from copy import deepcopy
from unittest import mock

import fc.check_ceph.check_snapshot_restore as snapcheck
import pytest
from rbd import ImageNotFound


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
    snapshot.pool.root.usage = 2000
    snapshot.size = 1000

    return snapshot


@pytest.fixture
def snap_warn(snapshot):
    snapshot = deepcopy(snapshot)
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.usage = 2000
    snapshot.size = 850000

    return snapshot


@pytest.fixture
def snap_critical(snapshot):
    snapshot = deepcopy(snapshot)
    snapshot.pool.root.size = 1000000
    snapshot.pool.root.usage = 2000
    snapshot.size = 950000

    return snapshot


# real-world mock data
class NautilusFillstatsConn:
    mon_command = mock.Mock(
        return_value=(
            0,
            json.dumps(
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
            ),
        )
    )


# ceph release specific collection of RBD mock classes
class IOCTXMockNautilus:
    """Does not really mock the internal structure of a real rbd.Ioctx, but serves as
    the shared data source for both our rbd.RBD and rbd.Image mocks to make them serve
    the same consistent list of images and snapshots.

    For now, comes pre-defined with a default map of images and snapshots, that can be
    modified though.
    """

    pool_image_data = {
        "rbd.hdd": {
            "test01": [
                {"name": "zerosnap", "size": 0},
                {"name": "backy-2342", "size": 2345678},
            ],
            "testdeleted": ImageNotFound("testdeleted"),
            "test02": [],
        },
        "rbd.ssd": {
            "test03": [
                {"name": "footest", "size": 1024},
            ],
        },
        "emptypool": {},
    }

    def __init__(self, poolname: str):
        self.poolname = poolname

    def close(self):
        pass


class RBDMockNautilus:
    def list(self, ioctxmock):
        return ioctxmock.pool_image_data[ioctxmock.poolname].keys()

    @staticmethod
    def __exception_raising_generator(iterable):
        """Helper generator that raises exception elements of other iterables."""
        it = iter(iterable)
        while True:
            try:
                next_el = next(it)
            except StopIteration:
                break
            if isinstance(next_el, Exception):
                raise next_el
            else:
                yield next_el


class ImageMockNautilus:
    def __init__(self, ioctxmock, imgname):
        try:
            ioctxmock.pool_image_data[ioctxmock.poolname][imgname]
        except KeyError:
            raise rbd.ImageNotFound(imgname)
        else:
            self.ioctxmock = ioctxmock
            self.imgname = imgname

    def list_snaps(self):
        snaplist = self.ioctxmock.pool_image_data[self.ioctxmock.poolname][
            self.imgname
        ]
        if isinstance(snaplist, Exception):
            raise snaplist
        else:
            return snaplist


@pytest.fixture(
    params=[(IOCTXMockNautilus, RBDMockNautilus, ImageMockNautilus)]
)
def rbd_image_mock(monkeypatch, request):
    """Monkeypatches the rbd.RBD and rbd.Image classes to be replaced with our mocks.
    These mocks share an rbd.Ioctx mock as a data source. This Ioctx mock class
    (not instance) is returned
    for later instrumentation or data customisation in the actual test."""

    (IoctxMockClass, RbdMockClass, ImageMockClass) = request.param
    # monkeypatch away the original rbd module classes
    monkeypatch.setattr("rbd.RBD", RbdMockClass)
    monkeypatch.setattr("rbd.Image", ImageMockClass)

    return IoctxMockClass


@pytest.fixture
def poolio_connection_mock(rbd_image_mock):
    class ConnMock:
        @staticmethod
        def open_ioctx(poolname):
            return rbd_image_mock(poolname)

    return ConnMock()


# already prepare possibility of testing with different ceph release outputs
@pytest.fixture(params=[NautilusFillstatsConn])
def raw_cluster_stats_conn(request):
    return request.param()


@pytest.fixture
def parsed_raw_cluster_fillstats(raw_cluster_stats_conn):
    """returns the still almost raw, but only slightly pre-processed ceph cluster
    fill stats as input for further parsing"""
    return snapcheck._ceph_osd_df_tree_roots(raw_cluster_stats_conn)


@pytest.fixture
def default_pool_roots():
    return {
        "default": ["rbd.hdd"],
        "ssd": ["rbd.ssd"],
    }
