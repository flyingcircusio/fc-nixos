import fc.ceph.main
import pytest


def test_main():
    with pytest.raises(SystemExit):
        fc.ceph.main.main(['--help'])
