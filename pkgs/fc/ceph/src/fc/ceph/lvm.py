import glob
import os
import os.path
import re
import time
from subprocess import CalledProcessError
from typing import Optional

import fc.ceph.luks
from fc.ceph.util import console, mount_status, run


class GenericLogicalVolume:
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
        cls, name, vg_name, disk, encrypt, size
    ) -> "GenericLogicalVolume":
        if cls.exists(name):
            raise RuntimeError("Volume already exists.")
        lv_factory = EncryptedLogicalVolume if encrypt else LogicalVolume
        lv = lv_factory(name)
        lv._create(disk=disk, size=size, vg_name=vg_name)
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

    def _create(self, disk: str, size: str, vg_name: str):
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

    def _create(self, disk: str, size: str, vg_name: str):
        self.ensure_vg(vg_name, disk)

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
    def ensure_vg(vg_name: str, disk: str):
        if vg_name in vg_names():
            return
        run.sgdisk("-Z", disk)
        run.sgdisk("-a", "8192", "-n", "1:0:0", "-t", "1:8e00", disk)

        for partition in [f"{disk}1", f"{disk}p1"]:
            if os.path.exists(partition):
                break
        else:
            raise RuntimeError(f"Could not find partition for PV on {disk}")

        run.pvcreate(partition)
        run.vgcreate(vg_name, partition)

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

    def __init__(self, name):
        self.name = name
        self.underlay = LogicalVolume(name + self.SUFFIX)
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

    def _create(self, disk: str, size: str, vg_name: str):
        self.underlay.create(
            name=self.underlay.name,
            disk=disk,
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
            "luksFormat",
            "--key-slot", str(fc.ceph.luks.KEYSTORE.slots["local"]),
            "-d", fc.ceph.luks.KEYSTORE.local_key_path(),
            self.underlay.device,
            "--pbkdf=argon2id",
            # fmt: on
        )

        self.cryptsetup(
            # fmt: off
            "-q",
            "luksAddKey",
            "-d", fc.ceph.luks.KEYSTORE.local_key_path(),
            self.underlay.device,
            "--key-slot", str(fc.ceph.luks.KEYSTORE.slots["admin"]),
            "--pbkdf=argon2id",
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
        """convention: also calls activate() at the end"""
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


class XFSCephVolume(GenericCephVolume):
    MKFS_XFS_OPTS = ["-m", "crc=1,finobt=1", "-i", "size=2048", "-K"]
    MOUNT_XFS_OPTS = "nodev,nosuid,noatime,nodiratime,logbsize=256k"

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
        print(f"Creating data volume on {disk or vg_name}...")
        self.lv = GenericLogicalVolume.create(
            name=self.name,
            vg_name=vg_name,
            disk=disk,
            encrypt=encrypt,
            size=size,
        )
        # Create OSD filesystem
        run.mkfs_xfs(
            # fmt: off
            "-f",
            "-L", self.name,
            *self.MKFS_XFS_OPTS,
            self.device,
            # fmt: on
        )
        run.sync()
        self.activate()

    def activate(self):
        self.lv.activate()
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
                "-t", "xfs", "-o", self.MOUNT_XFS_OPTS,
                self.device, self.mountpoint,
                # fmt: on
            )
        elif mount_device != self.lv.expected_mapper_name:
            raise RuntimeError(
                f"Mountpoint is using unexpected device `{mount_device}`."
            )

    def purge(self, lv_only=False):
        if os.path.exists(self.mountpoint):
            run.umount("-f", self.mountpoint, check=False)
            os.rmdir(self.mountpoint)

        if self.lv:
            self.lv.purge(lv_only)

    @property
    def encrypted(self) -> bool:
        return self.lv.encrypted
