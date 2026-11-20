"""Smoke tests for `--discard`: from the CLI down to `blkdiscard`.

The flag is threaded through a long chain of signatures, so these tests cover
it as a chain of links: CLI -> OSD object -> the three OSD volumes -> the base
disk that is actually TRIMmed. `osd prepare-journal` uses no additional volume
abstraction and therefore gets its own end-to-end assertion.
"""

from unittest import mock

import pytest
from fc.ceph.lvm import GenericLogicalVolume, XFSVolume
from fc.ceph.osd.nautilus import BlockVolume, BlueStoreOSD, WALVolume


class StopAfterVolumes(Exception):
    """Ends a command once `--discard` has arrived where we assert on it."""


@pytest.fixture
def no_lvs(monkeypatch):
    """Every volume constructor probes for pre-existing LVs."""
    monkeypatch.setattr("fc.ceph.lvm.run.json.lvs", lambda *a, **kw: [])


@pytest.mark.parametrize(
    "flags, expected", [(["--discard"], True), ([], False)]
)
def test_osd_create_bluestore_command_invocation(
    monkeypatch, tmp_path, fc_ceph_conf, no_lvs, flags, expected
):
    """`--discard` travels from the command line into the new OSD."""
    from fc.ceph.main import ceph

    device = tmp_path / "sdx"
    device.touch()
    monkeypatch.setattr("fc.ceph.lvm.run.json.vgs", lambda *a, **kw: [])
    monkeypatch.setattr(
        "fc.ceph.osd.nautilus.run.json.ceph", lambda *a, **kw: {"osdid": "0"}
    )
    monkeypatch.setattr("fc.ceph.osd.nautilus.run.systemctl", mock.Mock())
    created = {}

    def create(self, disk, **kwargs):
        created.update(disk=disk, **kwargs)

    monkeypatch.setattr(BlueStoreOSD, "create", create)

    ceph(["osd", "create-bluestore", str(device), "--no-encrypt", *flags])

    assert created["disk"] == str(device)
    assert created["discard"] is expected


def test_bluestore_osd_passes_discard_to_all_its_volumes(monkeypatch, no_lvs):
    """All three OSD volumes are asked to discard their base disk."""
    volumes = {}

    def call_recorder(name, last=False):
        def create(self, *args, **kwargs):
            volumes[name] = kwargs
            if last:
                raise StopAfterVolumes()

        return create

    monkeypatch.setattr(WALVolume, "create", call_recorder("wal"))
    monkeypatch.setattr(XFSVolume, "create", call_recorder("data"))
    monkeypatch.setattr(
        BlockVolume, "create", call_recorder("block", last=True)
    )

    with pytest.raises(StopAfterVolumes):
        BlueStoreOSD(0).create(
            "/dev/sdx",
            encrypt=False,
            wal_location="internal",
            crush_location="host=test",
            discard=True,
        )

    assert {name: kw["discard"] for name, kw in volumes.items()} == {
        "wal": True,
        "data": True,
        "block": True,
    }


@pytest.fixture
def blkdiscard(monkeypatch):
    """Records every TRIM; `run` is a single instance shared by all modules."""
    calls = mock.Mock()
    monkeypatch.setattr("fc.ceph.util.run.blkdiscard", calls)
    return calls


@pytest.fixture
def volume_without_lvm(monkeypatch, no_lvs):
    """Cut the LV/mkfs/mount tail off, so only disk handling is exercised."""
    monkeypatch.setattr(
        GenericLogicalVolume,
        "create",
        classmethod(lambda cls, **kw: mock.Mock()),
    )
    monkeypatch.setattr(XFSVolume, "mkfs", mock.Mock())
    monkeypatch.setattr(XFSVolume, "activate", mock.Mock())


@pytest.mark.parametrize("discard, calls", [(True, 1), (False, 0)])
def test_volume_discards_its_base_disk(
    monkeypatch, tmp_path, volume_without_lvm, blkdiscard, discard, calls
):
    """Only with `discard` the base disk is TRIMmed before partitioning."""
    monkeypatch.setattr("fc.ceph.lvm.run.sgdisk", mock.Mock())
    monkeypatch.setattr("fc.ceph.lvm.run.partprobe", mock.Mock())
    disk = str(tmp_path / "sdx")

    XFSVolume("ceph-osd-0", str(tmp_path / "mnt")).create(
        "vgosd-0", "1g", disk=disk, discard=discard
    )

    assert blkdiscard.mock_calls == [mock.call(disk)] * calls


def test_volume_warns_when_discard_has_no_disk(
    tmp_path, capsys, volume_without_lvm, blkdiscard
):
    """Without a base disk we cannot determine the base disk to be TRIMmed
    without potentially affecting other volumes.
    """
    XFSVolume("ceph-mon", str(tmp_path / "mnt")).create(
        "vgjnl00", "8g", discard=True
    )

    out = capsys.readouterr().out
    assert "WARNING" in out
    assert "discard" in out
    assert blkdiscard.mock_calls == []


@pytest.mark.parametrize("flags, calls", [(["--discard"], 1), ([], 0)])
def test_osd_prepare_journal_command_invocation(
    monkeypatch, tmp_path, fc_ceph_conf, blkdiscard, flags, calls
):
    """`osd prepare-journal --discard` TRIMs the raw journal disk."""
    from fc.ceph.main import ceph

    device = tmp_path / "sdy"
    device.touch()
    partition = tmp_path / "sdy1"
    monkeypatch.setattr(
        "fc.ceph.osd.nautilus.run.json.sfdisk",
        lambda *a, **kw: {"partitiontable": {"partitions": []}},
    )
    monkeypatch.setattr("fc.ceph.lvm.run.json.vgs", lambda *a, **kw: [])
    monkeypatch.setattr(
        "fc.ceph.osd.nautilus.run.json.vgs", lambda *a, **kw: []
    )
    for tool in ["sgdisk", "pvcreate", "vgcreate"]:
        monkeypatch.setattr(f"fc.ceph.osd.nautilus.run.{tool}", mock.Mock())
    # partprobe is what makes the kernel see the new partition
    monkeypatch.setattr(
        "fc.ceph.osd.nautilus.run.partprobe",
        mock.Mock(side_effect=lambda *a: partition.touch()),
    )

    ceph(["osd", "prepare-journal", str(device), *flags])

    assert blkdiscard.mock_calls == [mock.call(str(device))] * calls


def test_osd_rebuild_command_invocation(monkeypatch, fc_ceph_conf):
    """`--discard` is handed to the OSD that is being rebuilt."""
    from fc.ceph.main import ceph

    monkeypatch.setattr(
        "fc.ceph.lvm.run.json.vgs", lambda *a, **kw: [{"vg_name": "vgosd-0"}]
    )
    osd = mock.Mock()
    monkeypatch.setattr("fc.ceph.osd.nautilus.OSD", lambda id_: osd)

    ceph(["osd", "rebuild", "0", "--discard", "--no-encrypt"])

    assert osd.rebuild.call_args.kwargs["discard"] is True
