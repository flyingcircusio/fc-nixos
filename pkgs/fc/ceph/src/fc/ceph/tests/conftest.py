import fc.ceph.maintenance as maintSub
import fc.ceph.util
import pytest


@pytest.fixture(params=[maintSub.nautilus])
def maintenance_manager_legacy(request):
    """returns a maintenance manager for all Ceph releases supported by fc-ceph"""
    return request.param


@pytest.fixture
def maintenance_manager():
    """returns a maintenance manager just for the latest Ceph release supported by fc-ceph"""
    return maintSub.nautilus
