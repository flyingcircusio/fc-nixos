from unittest.mock import Mock
import pkg_resources
import pytest

from ..cluster import Cluster


@pytest.fixture
def cluster():
    return Cluster(
        pkg_resources.resource_filename(__name__, "fixtures/ceph.conf")
    )


@pytest.fixture
def osd_tree_json(monkeypatch):
    # most unnecessary properties have been removed for brevity
    mock_tree = {
        "nodes": [
            {"id": -10, "name": "ssd", "type": "root", "children": [-9]},
            {
                "id": -9,
                "name": "dev-ssd",
                "type": "datacenter",
                "children": [-8],
            },
            {
                "id": -8,
                "name": "devrack-ssd",
                "type": "rack",
                "children": [
                    -16,
                    -11,
                ],
            },
            {
                "id": -11,
                "name": "cartman09-ssd",
                "type": "host",
                "children": [13],
            },
            {
                "id": 13,
                "name": "osd.13",
                "type": "osd",
            },
            {
                "id": -16,
                "name": "cartman37-ssd",
                "type": "host",
                "children": [2],
            },
            {
                "id": 2,
                "name": "osd.2",
                "type": "osd",
            },
            {"id": -1, "name": "default", "type": "root", "children": [-2]},
            {"id": -2, "name": "dev", "type": "datacenter", "children": [-5]},
            {
                "id": -5,
                "name": "devrack",
                "type": "rack",
                "children": [
                    -13,
                    -7,
                ],
            },
            {
                "id": -7,
                "name": "cartman09",
                "type": "host",
                "children": [
                    17,
                    11,
                ],
            },
            {
                "id": 11,
                "name": "osd.11",
                "type": "osd",
            },
            {
                "id": 17,
                "name": "osd.17",
                "type": "osd",
            },
            {
                "id": -13,
                "name": "cartman37",
                "type": "host",
                "type_id": 1,
                "pool_weights": {},
                "children": [
                    # osd referenced but data missing -> host not counted
                    1
                ],
            },
        ]
    }
    call_mock = Mock(return_value=mock_tree)
    monkeypatch.setattr("fc.ceph.api.cluster.run.json.ceph", call_mock)
    return call_mock


class TestCluster(object):
    def test_default_pool_size(self, cluster):
        assert (2, 1) == cluster.default_pool_size()

    def test_default_pg_num(self, cluster):
        assert 32 == cluster.default_pg_num()

    def test_num_hosts_per_root_counts(self, cluster, osd_tree_json):
        assert cluster.num_hosts_per_root() == 1
        assert cluster.num_hosts_per_root("ssd") == 2
        with pytest.raises(ValueError):
            cluster.num_hosts_per_root("thisrootdoesnotexist")
