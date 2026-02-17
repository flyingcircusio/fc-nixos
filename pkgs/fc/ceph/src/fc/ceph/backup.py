import os

from fc.ceph.lvm import (
    AutomountActivationMixin,
    GenericLogicalVolume,
    MdraidDevice,
    XFSVolume,
)
from fc.ceph.util import console


class BackupManager:
    @staticmethod
    def create(
        name: str,
        vgname: str,
        disks: list[str],
        encrypt: bool,
        mountpoint: str,
        automount: bool,
    ):
        console.print(
            f"Creating new backup volume {vgname}/{name} on disks {', '.join(disks)}…"
        )
        vol = BackyVolume(name, mountpoint, automount)
        vol.create(disks, vgname, encrypt)


# XXX: Once the external crypt header logic is obsolete, we might be able to
# adopt XFSVolume for this directly.
class BackyVolume(AutomountActivationMixin):
    # nrext64 is default but requires kernel 6.6+
    MKFS_OPTS = ["-K", "-i", "nrext64=0"]
    MOUNT_OPTS = "nodev,nosuid,noatime,nodiratime"
    FSTYPE = "xfs"

    def __init__(
        self,
        name: str,
        mountpoint: str,
        automount=True,  # generally, this is created on backy servers that already have the mountpoint configured
    ):
        self.name = name
        self.mountpoint = mountpoint
        self.automount = automount
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
        XFSVolume.mkfs(self.device, self.name, self.MKFS_OPTS)

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
                        break
                    case _:
                        console.print("invalid choice, retry.")

        self.activate()

    def activate(self):
        self.lv.activate()
        super().activate()
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
