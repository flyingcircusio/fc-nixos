import glob
import os
import os.path
import re
import time
from socket import gethostname
from subprocess import CalledProcessError
from typing import Optional

import fc.ceph.luks
from fc.ceph.util import console, mount_status, run


class GenericBlockDevice:
    def __new__(cls, name: str):
        # prevent explicitly instantiated child classes from returning as None
        if cls is not GenericLogicalVolume:
            return object.__new__(cls)
        if MdraidDevice.exists(name):
            return MdraidDevice(name)
        elif PartitionedDisk.exists(name):
            return PartitionedDisk(name)
        # Allow operations to proceed by creating a block device
        return None

    def __init__(self, name: str):
        self.name = name

    # create cannot be a generic method, as it requires different params depending on the type
    @property
    def blockdevice(self) -> str:
        raise NotImplementedError

    @classmethod
    def exists(cls, name: str) -> bool:
        raise NotImplementedError


class MdraidDevice(GenericBlockDevice):
    """represents a software RAID array in mode RAID6 with spare disk. Uses the
    whole provided blockdevices without partitioning."""

    @classmethod
    def create(
        cls,
        name: str,
        # The mdraid individual member disks could also be generalised as
        # GenericBlockDevices itself, but for simplicity directly use
        # concrete string device paths here.
        blockdevices: list[str],
    ):
        main_disks = blockdevices[:-1]
        if main_disks:
            spare_disk = blockdevices[-1]
        else:
            raise RuntimeError(
                "MdraidDevice: at least 2 disks required. Aborting."
            )
        obj = cls(name)
        run.mdadm(
            "--create",
            f"/dev/md/{obj.name}",
            "--level=6",
            f"--raid-devices={len(main_disks)}",
            *main_disks,
        )
        # add spare disk
        run.mdadm("--add", obj.blockdevice, spare_disk)
        return obj

    def __init__(self, name: str):
        self.name = name

    @property
    def blockdevice(self) -> str:
        return self._bdname(self.name)

    @staticmethod
    def _bdname(name: str) -> str:
        # By default, mdadm records the hostname of the host where the raid has
        # been created in the superblock. This hostname becomes part of the
        # device symlink name.
        # Here we assume that RAID devices are not moved between hosts.
        return f"/dev/disk/by-id/md-name-{gethostname()}:{name}"

    @classmethod
    def exists(cls, name) -> bool:
        potential_name = cls._bdname(name)
        return (
            os.path.exists(potential_name)
            and os.path.exists(os.readlink(potential_name))
            and str(os.readlink(potential_name)).startswith("/dev/md")
        )

    # TODO do we need activating?


class PartitionedDisk(GenericBlockDevice):
    """name denotes the path to the whole unpartitioned disk"""

    def __init__(self, name: str):
        super().__init__(name)
        self._blockdevice: Optional[str] = None

    @staticmethod
    def _partition_candidates(disk: str) -> list[str]:
        return [f"{disk}1", f"{disk}p1"]

    @property
    def blockdevice(self):
        if not self._blockdevice:
            for partition in self._partition_candidates(self.name):
                if os.path.exists(partition):
                    self._blockdevice = partition
                    break
            else:
                raise RuntimeError(f"Could not find partition 1 on {self.name}")
        return self._blockdevice

    @classmethod
    def create(cls, disk: str) -> "PartitionedDisk":
        obj = cls(disk)
        run.sgdisk("-Z", disk)
        run.sgdisk("-a", "8192", "-n", "1:0:0", "-t", "1:8e00", disk)
        return obj

    @classmethod
    def exists(cls, name) -> bool:
        return any(
            [os.path.exists(part) for part in cls._partition_candidates(name)]
        )


class AutomountActivationMixin:
    automount: bool
    mountpoint: str
    FSTYPE: str
    MOUNT_OPTS: str

    def activate(self):
        mount_device = mount_status(self.mountpoint)
        if not os.path.exists(self.mountpoint):
            os.makedirs(self.mountpoint)

        if self.automount:
            time.sleep(1)
            try:
                run.mount(
                    self.mountpoint
                )  # device recreation does not always trigger automount
            except CalledProcessError as e:
                if e.returncode == 32:
                    # we take this as "already mounted", but device could also be busy
                    pass
                else:
                    raise e
            while not (mount_device := mount_status(self.mountpoint)):
                console.print(
                    "Waiting for mountpoint to be activated automatically ... ",
                    style="grey50",
                )
                time.sleep(1)
        if not mount_device:
            run.mount(
                # fmt: off
                "-t", self.FSTYPE, "-o", self.MOUNT_OPTS,
                self.device, self.mountpoint,
                # fmt: on
            )
        elif mount_device != self.lv.expected_mapper_name:
            raise RuntimeError(
                f"Mountpoint is using unexpected device `{mount_device}`."
            )


class GenericLogicalVolume:
    name: str

    def __new__(cls, name):
        # prevent explicitly instantiated child classes from returning as None
        if cls is not GenericLogicalVolume:
            return object.__new__(cls)
        if EncryptedLogicalVolume.exists(name):
            return EncryptedLogicalVolume(name)
        if LogicalVolume.exists(name):
            return LogicalVolume(name)
        # Allow operations to proceed by creating a volume.
        return None

    @classmethod
    def exists(cls, name):
        for provider in [EncryptedLogicalVolume, LogicalVolume]:
            if provider.exists(name):
                return True
        return False

    @classmethod
    def create(
        cls,
        name: str,
        vg_name: str,
        base_device: Optional[GenericBlockDevice],
        encrypt: bool,
        size,
    ) -> "GenericLogicalVolume":
        if cls.exists(name):
            raise RuntimeError("Volume already exists.")
        lv_factory = EncryptedLogicalVolume if encrypt else LogicalVolume
        lv = lv_factory(name)
        lv._create(base_device=base_device, size=size, vg_name=vg_name)
        return lv

    @property
    def device(self) -> str:
        """Returns the path to the blockdevice file of the volume.
        Also ensures that the file is present by activating the volume if
        necessary.

        This is a design decision made due to some kinds of volumes requiring
        an `activate` first before their device path can be determined.
        For getting a uniform API, all volume types activate themselfs as a
        side effect of accessing this property.
        Volume types not requiring an activation for determining the path might
        optionally provide a `device_path` property."""
        raise NotImplementedError

    @property
    def base_disk(self) -> str:
        raise NotImplementedError

    @property
    def expected_mapper_name(self) -> str:
        raise NotImplementedError

    @property
    def encrypted(self):
        raise NotImplementedError

    def _create(
        self, base_device: Optional[GenericBlockDevice], size: str, vg_name: str
    ):
        raise NotImplementedError

    def purge(self, lv_only=False):
        raise NotImplementedError


class LogicalVolume(GenericLogicalVolume):
    def __init__(self, name: str) -> None:
        self.name = name
        self.escaped_name = re.escape(self.name)
        self._vg_name: Optional[str] = None

    @classmethod
    def exists(cls, name):
        return name in lv_names()

    @property
    def device(self) -> str:
        if not self._vg_name:
            self.activate()
        return f"/dev/{self._vg_name}/{self.name}"

    @property
    def base_disk(self) -> str:
        """Returns the underlying disk used for creating this volume, in LVM
        terminology that's the PV.
        Note: In principle, LVM volumes are able to use multiple PVs in parallel.
        Our abstraction assumes that only one PV is used by the LV.
        """
        pvs = run.json.pvs("-S", f"lv_name={self.name}", "--all")
        if not len(pvs) == 1:
            raise ValueError(
                f"Unexpected number of PVs in OSD's RG: {len(pvs)}"
            )
        pv = pvs[0]["pv_name"]
        # Find the parent
        for candidate in run.json.lsblk_linear(pv, "-o", "name,pkname"):
            if candidate["name"] == pv.split("/")[-1]:
                device = "/".join(["", "dev", candidate["pkname"]])
                break
        else:
            raise ValueError(f"Could not find parent for PV: {pv}")

        return device

    @property
    def expected_mapper_name(self) -> str:
        """
        Constructs the expected device mapper name from VG and LV, as it is
        returned by lsblk as "name"
        """

        def dmify(identifier: str):
            return "--".join(identifier.split("-"))

        if not self._vg_name:
            self.activate()
        assert self._vg_name is not None  # make MyPy happy
        return f"{dmify(self._vg_name)}-{dmify(self.name)}"

    @property
    def encrypted(self):
        return False

    def activate(self):
        # find LVM vg
        lv = run.json.lvs(
            "-S", f"lv_name=~^{self.escaped_name}$", "-o", "vg_name"
        )
        if (discovered_lvs := len(lv)) > 1:
            raise RuntimeError(
                f"Expected only one LV named {self.name}, but "
                f"found {discovered_lvs}.\nAborting."
            )
        elif discovered_lvs == 0:
            raise LookupError(
                f"No LV found named {self.name}, it might have "
                "been already deleted."
            )
        self._vg_name = lv[0]["vg_name"]

    def _create(
        self, base_device: Optional[GenericBlockDevice], size: str, vg_name: str
    ):
        self.ensure_vg(vg_name, base_device)

        # 3. Create OSD LV on remainder of the VG
        if "%" in size:
            # -l100%vg
            size = f"-l{size}"
        else:
            # -L1g
            size = f"-L{size}"
        run.lvcreate(
            # fmt: off
            "-W", "y", "-y",
            size, f"-n{self.name}",
            vg_name,
            # fmt: on
        )

    @staticmethod
    def ensure_vg(vg_name: str, base_device: Optional[GenericBlockDevice]):
        if vg_name in vg_names():
            return

        if not base_device:
            raise RuntimeError(
                f"VG {vg_name} not found and no base block device has been specified to create it on. Aborting."
            )

        blockdevice_underlay = base_device.blockdevice
        run.pvcreate(blockdevice_underlay)
        run.vgcreate(vg_name, blockdevice_underlay)

    def purge(self, lv_only=False):
        # Delete LVs
        try:
            run.wipefs("-q", "-a", self.device, check=False)
            run.lvremove("-f", self.device, check=False)
        except LookupError as e:
            print(e)
            print("Assuming the volume has already been deleted, skipping")
            return

        if lv_only:
            return

        try:
            pv = run.json.pvs("-S", f"vg_name=~^{re.escape(self._vg_name)}$")[0]
        except IndexError:
            pass
        else:
            run.vgremove("-f", self._vg_name, check=False)
            run.pvremove(pv["pv_name"], check=False)

        # XXX this doesn't really fit the abstraction, but IMHO it's fine to
        # assume that the data volume has an overarching meaning. we
        # call purge on the other volumes, too. Ideally OSDs should clean
        # up the other volumes first, I guess.

        # Force remove old mapper files
        delete_paths = (
            glob.glob(f"/dev/{self._vg_name}/*")
            + glob.glob(f"/dev/mapper/{self.expected_mapper_name}-*")
            + [f"/dev/{self._vg_name}"]
        )
        for x in delete_paths:
            if not os.path.exists(x):
                continue
            print(x)
            if os.path.isdir(x):
                os.rmdir(x)
            else:
                os.unlink(x)


class EncryptedLogicalVolume(GenericLogicalVolume):
    SUFFIX = "-crypted"

    def __init__(self, name: str):
        self.name = name
        self.underlay: GenericLogicalVolume = LogicalVolume(name + self.SUFFIX)
        self._device = f"/dev/mapper/{self.name}"
        self._ready = False

    @classmethod
    def exists(cls, name):
        return LogicalVolume.exists(name + cls.SUFFIX)

    @property
    def device(self) -> str:
        if not self._ready:
            self.activate()
        return self._device

    @property
    def device_path(self) -> str:
        """
        Additional property to `device`, which returns the path to the volume's
        block device without activating the volume and ensuring that a file is
        actually present there.
        """
        return self._device

    @property
    def base_disk(self) -> str:
        return self.underlay.base_disk

    @property
    def expected_mapper_name(self) -> str:
        return self.name

    def _create(
        self, base_device: Optional[GenericBlockDevice], size: str, vg_name: str
    ):
        self.underlay.create(
            name=self.underlay.name,
            base_device=base_device,
            size=size,
            vg_name=vg_name,
            encrypt=False,
        )

        # FIXME: handle keyfile not found errors,
        print(f"Encrypting volume {self.name} ...")
        self.cryptsetup(
            # fmt: off
            "-q",
            *self._tunables_sectorsize,
            *self._tunables_luks_header,
            *self._tunables_cipher,
            "luksFormat",
            "--key-slot", str(fc.ceph.luks.KEYSTORE.slots["local"]),
            "-d", fc.ceph.luks.KEYSTORE.local_key_path(),
            self.underlay.device,
            # fmt: on
        )

        self.cryptsetup(
            # fmt: off
            "-q",
            *self._tunables_luks_header,
            "luksAddKey",
            "-d", fc.ceph.luks.KEYSTORE.local_key_path(),
            self.underlay.device,
            "--key-slot", str(fc.ceph.luks.KEYSTORE.slots["admin"]),
            "-",
            input=fc.ceph.luks.KEYSTORE.admin_key_for_input()
            # fmt: on
        )

    @property
    def encrypted(self):
        return True

    def activate(self):
        self.underlay.activate()
        # FIXME: needs error catching and handling; adding that makes sense
        # once we know the role of systemd/udev in the activation cycle
        if not os.path.exists(self.device_path):
            self.cryptsetup(
                # fmt: off
                "-q",
                "--allow-discards",     # pass throught TRIM commands to disk
                "open",
                "-d", fc.ceph.luks.KEYSTORE.local_key_path(),
                self.underlay.device,
                self.name,
                # fmt: on
            )
        self._ready = True

    def deactivate(self):
        if self._ready or os.path.exists(self.device_path):
            self.cryptsetup("-q", "close", self.name)

    def purge(self, lv_only=False):
        self.deactivate()
        self.cryptsetup("-q", "erase", self.underlay.device)
        self.underlay.purge(lv_only)

    cryptsetup_tunables = [
        # fmt: off
        # inspired by the measurements done in https://ceph.io/en/news/blog/2023/ceph-encryption-performance/:
        "--perf-submit_from_crypt_cpus",
        # for larger writes throughput
        # might be useful as well and is discussed to be enabled in Ceph,
        # but requires kernel >=5.9: https://github.com/ceph/ceph/pull/49554
        # especially relevant for SSDs, see https://blog.cloudflare.com/speeding-up-linux-disk-encryption/
        # "--perf-no_read_workqueue", "--perf-no_write_workqueue"
        # fmt: on
    ]
    # reduce CPU load for larger writes, can be removed after cryptsetup >=2.40
    _tunables_sectorsize = ("--sector-size", "4096")

    # FIXME: probably want to move these pinned parameters over to luks.py,
    # they don't just affect ceph

    # tunables that apply when (re)creating a LUKS volume and its data or reencrypting it
    _tunables_cipher = (
        # fmt: off
        "--cipher", "aes-xts-plain64",
        "--key-size", "512",
        # fmt: on
    )
    # tunables that apply when (re)creating a LUKS volume header
    _tunables_luks_header = (
        # fmt: off
        "--pbkdf", "argon2id",
        "--type", "luks2",
        # fmt: on
    )

    @classmethod
    def cryptsetup(cls, *args: str, **kwargs):
        """cryptsetup wrapper that adds default tunable options to the calls"""
        return run.cryptsetup(*cls.cryptsetup_tunables, *args, **kwargs)


def lv_names():
    return set(lv["lv_name"] for lv in run.json.lvs())


def vg_names():
    return set(vg["vg_name"] for vg in run.json.vgs())


class GenericCephVolume:
    @property
    def device(self) -> str:
        raise NotImplementedError

    @property
    def exists(self) -> bool:
        raise NotImplementedError

    def __init__(self, osd_id: str):
        raise NotImplementedError

    def create(
        self,
        vg_name: str,
        size: str,
        disk: Optional[str] = None,
        encrypt: bool = False,
    ):
        """The `disk` argument is optional and only considered for when the
        VG does not exists yet. If a VG called `vg_name` can be found, `disk`
        is ignored.

        convention: also calls activate() at the end"""
        raise NotImplementedError

    def activate(self):
        raise NotImplementedError

    def actual_size(self):
        return int(run.blockdev("--getsize64", self.device).strip())

    def purge(self):
        raise NotImplementedError

    @staticmethod
    def list_local_osd_ids():
        vgs = run.json.vgs("-S", r"vg_name=~^vgosd\-[0-9]+$")
        return [int(vg["vg_name"].replace("vgosd-", "", 1)) for vg in vgs]


# TODO: name can be a bit misleading, as we also utilise this for the XFS key volume
class XFSCephVolume(AutomountActivationMixin, GenericCephVolume):
    MKFS_OPTS = ["-m", "crc=1,finobt=1", "-i", "size=2048", "-K"]
    MOUNT_OPTS = "nodev,nosuid,noatime,nodiratime,logbsize=256k"
    FSTYPE = "xfs"

    def __init__(self, name: str, mountpoint: str, automount=False):
        self.name = name
        self.mountpoint = mountpoint
        self.automount = automount
        self.lv = GenericLogicalVolume(self.name)

    @property
    def device(self):
        return self.lv.device

    @property
    def exists(self) -> bool:
        return self.lv.exists(self.name)

    def create(
        self,
        vg_name: str,
        size: str,
        disk: Optional[str] = None,
        encrypt: bool = False,
    ):
        """The `disk` argument is optional and only considered for when the
        VG does not exists yet. If a VG called `vg_name` can be found, `disk`
        is ignored.
        """
        print(f"Creating data volume on {disk or vg_name}...")
        disk_block = PartitionedDisk.create(disk) if disk else None
        self.lv = GenericLogicalVolume.create(
            name=self.name,
            vg_name=vg_name,
            base_device=disk_block,
            encrypt=encrypt,
            size=size,
        )
        # Create OSD filesystem
        run.mkfs_xfs(
            # fmt: off
            "-f",
            "-L", self.name,
            *self.MKFS_OPTS,
            self.device,
            # fmt: on
        )
        run.sync()
        self.activate()

    def activate(self):
        self.lv.activate()

        super().activate()

    def purge(self, lv_only=False):
        if os.path.exists(self.mountpoint):
            run.umount("-f", self.mountpoint, check=False)
            os.rmdir(self.mountpoint)

        if self.lv:
            self.lv.purge(lv_only)

    @property
    def encrypted(self) -> bool:
        return self.lv.encrypted
