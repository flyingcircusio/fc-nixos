from pathlib import Path
import pytest

from ..cluster import Cluster


@pytest.fixture
def cluster():
    # The file only exists in the code, but not in the built library
    return Cluster(
        Path(__file__).parent / "fixtures/ceph.conf"
    )


class TestCluster(object):
    def test_default_pool_size(self, cluster):
        assert (2, 1) == cluster.default_pool_size()

    def test_default_pg_num(self, cluster):
        assert 32 == cluster.default_pg_num()
