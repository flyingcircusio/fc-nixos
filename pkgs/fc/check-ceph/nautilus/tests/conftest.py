import pytest
from rbd import ImageNotFound

# real-world mock data
nautilus_cluster_stats = {
    "ssd": {
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
    "default": {
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
}
nautilus_snap_data = {
    "imgname": "litdev00.root",
    "snapname": "backy-v5nhkWuJ83FTaxgrVaH4Jm",
    "size_bytes": 805306368000,
}

# already prepare possibility of testing with different ceph release outputs
@pytest.fixture(params=[nautilus_cluster_stats])
def cluster_stats(request):
    return request.param


@pytest.fixture(params=[nautilus_snap_data])
def snap_data(request):
    return request.param


@pytest.fixture
def default_pool_roots():
    return {
        "default": ["rbd.hdd"],
        "ssd": ["rbd.ssd"],
    }


# ceph release specific collection of RBD mock classes
class IOCTXMockNautilus:
    """Does not really mock the internal structure of a real rbd.Ioctx, but serves as
    the shared data source for both our rbd.RBD and rbd.Image mocks to make them serve
    the same consistent list of images and snapshots.

    For now, comes pre-defined with a default map of images and snapshots, that can be
    modified though.
    """

    def __init__(self, poolname: str = "rbd.hdd"):
        self.poolname = poolname

        self._image_data = {
            "test01": [
                {"name": "zerosnap", "size": 0},
                {"name": "backy-2342", "size": 2345678},
            ],
            "testdeleted": ImageNotFound("testdeleted"),
            "test02": [],
            "test03": [
                {"name": "footest", "size": 1024},
            ],
        }


class RBDMockNautilus:
    def list(self, ioctxmock):
        return ioctxmock._image_data.keys()

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
            ioctxmock._image_data[imgname]
        except KeyError:
            raise rbd.ImageNotFound(imgname)
        else:
            self.data_source = ioctxmock
            self.imgname = imgname

    def list_snaps(self):
        snaplist = self.data_source._image_data[self.imgname]
        if isinstance(snaplist, Exception):
            raise snaplist
        else:
            return snaplist


@pytest.fixture(
    params=[(IOCTXMockNautilus, RBDMockNautilus, ImageMockNautilus)]
)
def rbd_image_mock(monkeypatch, request):
    """Monkeypatches the rbd.RBD and rbd.Image classes to be replaced with our mocks.
    These mocks share an rbd.Ioctx mock as a data source. This Ioctx mock is returned
    for later instrumentation or data customisation in the actual test."""

    (IoctxMockClass, RbdMockClass, ImageMockClass) = request.param
    ioctxmock = IoctxMockClass()
    # monkeypatch away the original rbd module classes
    monkeypatch.setattr("rbd.RBD", RbdMockClass)
    monkeypatch.setattr("rbd.Image", ImageMockClass)

    return ioctxmock
