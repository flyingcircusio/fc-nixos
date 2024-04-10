import os

from fc.ceph.lvm import (
    AutomountActivationMixin,
    GenericLogicalVolume,
    MdraidDevice,
)
from fc.ceph.util import console, run


class BackupManager:
    @staticmethod
    def create(
        name: str, vgname: str, disks: list[str], encrypt: bool, mountpoint: str
    ):
        console.print(
            f"Creating new backup volume {vgname}/{name} on disks {', '.join(disks)}…"
        )
        vol = BackyVolume(name, mountpoint)
        vol.create(disks, vgname, encrypt)


class BackyVolume:
    MKFS_OPTS = ["-K"]
    MOUNT_OPTS = "nodev,nosuid,noatime,nodiratime"

    def __init__(self, name: str, mountpoint: str):
        self.name = name
        self.mountpoint = mountpoint
        self.lv = GenericLogicalVolume(self.name)

    def create(
        self, blockdevices: list[str], vgname: str, encrypt: bool = True
    ):
        # underlay Mdraid hopefully always self-assembles, no need to keep an
        # instance-wide reference after successful creation
        raid = MdraidDevice.create(self.name, blockdevices)
        self.lv = GenericLogicalVolume.create(
            self.name, vgname, raid, encrypt, size="100%vg"
        )
        run.mkfs_xfs(
            # fmt: off
            "-f",
            "-L", self.name,
            *self.MKFS_OPTS,
            self.device
        )
        run.sync()

        if os.path.exists(ext_header := f"{self.mountpoint}.luks"):
            console.print(
                f"Found a stale external LUKS header from a previous volume in {ext_header}."
            )
            while True:
                resp = input("Delete the file? y/[n]")
                match resp:
                    case "y":
                        os.remove(ext_header)
                        break
                    case "n" | "":
                        breakpoint
                    case _:
                        console.print("invalid choice, retry.")

        self.activate()

    def activate(self):
        self.lv.activate()
        # for the mdraid, we rely on the OS for automatically assembling it

    @property
    def encrypted(self) -> bool:
        return self.lv.encrypted

    @property
    def exists(self) -> bool:
        return self.lv.exists(self.name)

    @property
    def device(self):
        return self.lv.device
