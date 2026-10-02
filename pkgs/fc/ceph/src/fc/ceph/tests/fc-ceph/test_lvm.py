from subprocess import CalledProcessError
from unittest import mock

import pytest

from fc.ceph.lvm import XFSVolume


class FailNTimes:
    """Helper that raises an exception for the first N calls, then succeeds."""

    def __init__(self, exception, fail_count):
        self.exception = exception
        self.fail_count = fail_count
        self.call_count = 0

    def __call__(self, *args):
        self.call_count += 1
        if self.call_count <= self.fail_count:
            raise self.exception


def test_mkfs_success_first_attempt(monkeypatch):
    """mkfs succeeds on first attempt."""
    mock_mkfs = mock.Mock()
    mock_sync = mock.Mock()
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_xfs", mock_mkfs)
    monkeypatch.setattr("fc.ceph.lvm.run.sync", mock_sync)

    XFSVolume.mkfs("/dev/test", "testlabel", ["-K"])

    mock_mkfs.assert_called_once_with("-f", "-L", "testlabel", "-K", "/dev/test")
    mock_sync.assert_called_once()


def test_mkfs_retries_on_device_busy(monkeypatch):
    """mkfs retries when device is busy, then succeeds."""
    busy_error = CalledProcessError(1, "mkfs.xfs")
    busy_error.stderr = (
        b"mkfs.xfs: cannot open /dev/test: Device or resource busy"
    )

    fail_twice = FailNTimes(busy_error, fail_count=2)
    mock_sync = mock.Mock()
    mock_udevadm = mock.Mock()
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_xfs", fail_twice)
    monkeypatch.setattr("fc.ceph.lvm.run.sync", mock_sync)
    monkeypatch.setattr("fc.ceph.lvm.run.udevadm", mock_udevadm)

    XFSVolume.mkfs("/dev/test", "testlabel", ["-K"])

    assert fail_twice.call_count == 3
    assert mock_udevadm.call_count == 2
    mock_udevadm.assert_called_with("settle")
    mock_sync.assert_called_once()


def test_mkfs_raises_after_max_retries(monkeypatch):
    """mkfs raises after exhausting all retries."""
    busy_error = CalledProcessError(1, "mkfs.xfs")
    busy_error.stderr = (
        b"mkfs.xfs: cannot open /dev/test: Device or resource busy"
    )

    mock_mkfs = mock.Mock(side_effect=busy_error)
    mock_udevadm = mock.Mock()
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_xfs", mock_mkfs)
    monkeypatch.setattr("fc.ceph.lvm.run.udevadm", mock_udevadm)

    with pytest.raises(CalledProcessError):
        XFSVolume.mkfs("/dev/test", "testlabel", ["-K"], retries=3)

    assert mock_mkfs.call_count == 3
    assert mock_udevadm.call_count == 2


def test_mkfs_raises_immediately_on_other_errors(monkeypatch):
    """mkfs raises immediately for non-busy errors."""
    other_error = CalledProcessError(1, "mkfs.xfs")
    other_error.stderr = b"mkfs.xfs: /dev/test is not a block device"

    mock_mkfs = mock.Mock(side_effect=other_error)
    mock_udevadm = mock.Mock()
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_xfs", mock_mkfs)
    monkeypatch.setattr("fc.ceph.lvm.run.udevadm", mock_udevadm)

    with pytest.raises(CalledProcessError):
        XFSVolume.mkfs("/dev/test", "testlabel", ["-K"])

    mock_mkfs.assert_called_once()
    mock_udevadm.assert_not_called()


def test_mkfs_handles_none_stderr(monkeypatch):
    """mkfs handles CalledProcessError with None stderr."""
    error = CalledProcessError(1, "mkfs.xfs")
    error.stderr = None

    mock_mkfs = mock.Mock(side_effect=error)
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_xfs", mock_mkfs)

    with pytest.raises(CalledProcessError):
        XFSVolume.mkfs("/dev/test", "testlabel", ["-K"])

    mock_mkfs.assert_called_once()


def test_ext4_volume_uses_mkfs_ext4(monkeypatch):
    """mkfs passes ext4's own force flag and options."""
    from fc.ceph.lvm import Ext4Volume

    mock_mkfs = mock.Mock()
    monkeypatch.setattr("fc.ceph.lvm.run.mkfs_ext4", mock_mkfs)
    monkeypatch.setattr("fc.ceph.lvm.run.sync", mock.Mock())

    Ext4Volume.mkfs("/dev/sdj", "keys", Ext4Volume.MKFS_OPTS)

    mock_mkfs.assert_called_once_with("-F", "-L", "keys", "-m", "0", "/dev/sdj")


def test_keystore_volume_takes_the_whole_stick(monkeypatch, tmp_path):
    """The keystore volume is ext4 and sized by the whole VG."""
    from fc.ceph.luks.manage import LUKSKeyStoreManager
    from fc.ceph.lvm import Ext4Volume

    monkeypatch.setattr("fc.ceph.lvm.run.json.lvs", lambda *args, **kwargs: [])
    manager = LUKSKeyStoreManager()
    requested = {}

    def create(self, vg_name, size, device, **kwargs):
        requested.update(vg_name=vg_name, size=size, device=device)

    monkeypatch.setattr(Ext4Volume, "create", create)
    monkeypatch.setattr(manager._KEYSTORE, "local_key_path", lambda: str(tmp_path / "host.key"))
    monkeypatch.setattr("fc.ceph.luks.manage.shutil.chown", lambda *args, **kwargs: None)

    manager.create("/dev/sdj")

    assert isinstance(manager.volume, Ext4Volume)
    assert requested == {"vg_name": "vgkeys", "size": "100%vg", "device": "/dev/sdj"}
