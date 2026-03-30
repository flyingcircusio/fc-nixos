import pkg_resources
import pytest

from ..cluster import Cluster


@pytest.fixture
def cluster():
    return Cluster(
        pkg_resources.resource_filename(__name__, "fixtures/ceph.conf")
    )


class TestCluster(object):
    def test_default_pool_size(self, cluster):
        assert (2, 1) == cluster.default_pool_size()

    def test_default_pg_num(self, cluster):
        assert 32 == cluster.default_pg_num()
