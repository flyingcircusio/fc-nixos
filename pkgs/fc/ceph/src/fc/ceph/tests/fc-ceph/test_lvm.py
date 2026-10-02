import asyncio
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


def test_encrypted_activate_passes_the_key_on_stdin(monkeypatch):
    """The volume is opened with the key through stdin, not with `-d <file>`."""
    from fc.ceph.lvm import EncryptedLogicalVolume

    calls = []

    async def cryptsetup_async(*args, **kwargs):
        calls.append((args, kwargs))
        return b""

    monkeypatch.setattr(
        "fc.ceph.lvm.Cryptsetup.cryptsetup_async", cryptsetup_async
    )
    monkeypatch.setattr("fc.ceph.lvm.run.udevadm", mock.Mock())

    volume = EncryptedLogicalVolume("ceph-osd-5-block")
    volume.underlay._vg_name = "vgosd-5"
    monkeypatch.setattr(volume.underlay, "activate", mock.Mock())
    monkeypatch.setattr(
        EncryptedLogicalVolume,
        "device_path",
        property(lambda self: "/dev/does-not-exist"),
    )

    asyncio.run(volume.activate_async(b"admin-key"))

    assert calls == [
        (
            (
                "--allow-discards",
                "open",
                "--key-file=-",
                "/dev/vgosd-5/ceph-osd-5-block-crypted",
                "ceph-osd-5-block",
            ),
            {"input": b"admin-key"},
        )
    ]


def test_encrypted_activate_lets_cryptsetup_read_the_local_key(monkeypatch):
    """Without a key we hand over the path: the key never enters this process."""
    from fc.ceph.luks import KEYSTORE
    from fc.ceph.lvm import EncryptedLogicalVolume

    calls = []

    async def cryptsetup_async(*args, **kwargs):
        calls.append((args, kwargs))
        return b""

    monkeypatch.setattr(
        "fc.ceph.lvm.Cryptsetup.cryptsetup_async", cryptsetup_async
    )
    monkeypatch.setattr("fc.ceph.lvm.run.udevadm", mock.Mock())
    monkeypatch.setattr(KEYSTORE, "local_key_path", lambda: "/mnt/keys/test.key")

    volume = EncryptedLogicalVolume("ceph-osd-5-block")
    volume.underlay._vg_name = "vgosd-5"
    monkeypatch.setattr(volume.underlay, "activate", mock.Mock())
    monkeypatch.setattr(
        EncryptedLogicalVolume,
        "device_path",
        property(lambda self: "/dev/does-not-exist"),
    )

    volume.activate()

    assert calls == [
        (
            (
                "--allow-discards",
                "open",
                "--key-file=/mnt/keys/test.key",
                "/dev/vgosd-5/ceph-osd-5-block-crypted",
                "ceph-osd-5-block",
            ),
            {"input": None},
        )
    ]
