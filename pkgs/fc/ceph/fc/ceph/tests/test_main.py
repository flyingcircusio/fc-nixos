import pytest

import fc.ceph.main


def test_main():
    with pytest.raises(SystemExit):
        fc.ceph.main.main(["--help"])
