import fnmatch
import secrets
import shutil
from pathlib import Path
from typing import Optional

from fc.ceph.luks import KEYSTORE  # singleton
from fc.ceph.lvm import XFSCephVolume
from fc.ceph.util import console, run


class LUKSKeyStoreManager(object):
    def __init__(self):
        self.volume = XFSCephVolume("keys", "/mnt/keys", automount=True)
        self._KEYSTORE = KEYSTORE  # don't use directly, overridable in test

    def create(self, device):
        console.print(f"Creating keystore on {device} ...", style="bold")
        self.volume.create("vgkeys", "1g", device)
        console.print(
            f"Creating secret key in {self._KEYSTORE.local_key_path()} ...",
            style="bold",
        )

        keyfile = Path(self._KEYSTORE.local_key_path())
        with open(keyfile, "w") as f:
            keyfile.chmod(0o600)
            shutil.chown(keyfile, "root", "root")
            f.write(secrets.token_hex(512 // 8))
        console.print("Keystore created and initialized.", style="bold green")

    def destroy(self, overwrite=True):
        console.print(
            f"Destroying keystore in {self.volume.mountpoint} ...", style="bold"
        )
        base_disk = self.volume.lv.base_disk
        self.volume.purge()
        run.sgdisk("-Z", base_disk)

        if overwrite:
            console.print(f"Overwriting {base_disk} ...", style="bold")
            mappedname = base_disk.replace("/", "-")
            mappedname = mappedname.lstrip("-")
            run.cryptsetup(
                "open",
                "--type",
                "plain",
                "-d",
                "/dev/urandom",
                base_disk,
                mappedname,
            )
            run.dd(
                "if=/dev/zero",
                f"of=/dev/mapper/{mappedname}",
                "bs=4M",
                "status=progress",
                check=False,
            )
            run.cryptsetup("close", mappedname)
            console.print("Keystore destroyed.", style="bold green")
        else:
            console.print(
                "Keystore destroyed, but not overwritten.", style="bold yellow"
            )

    def rekey(
        self,
        lvs: Optional[str],
        device: Optional[str],
        header: Optional[str],
        slot="local",
    ):
        """Update keyslots, using the opposite key for assurance."""

        if slot == "local":
            console.print("Updating local machine key ...", style="bold")
        elif slot == "admin":
            console.print("Updating admin key ...", style="bold")
        else:
            raise ValueError(f"slot={slot}")

        if not (lvs or device):
            raise ValueError("Need to provide --lvs or --device.")
        if not bool(lvs) ^ bool(device):
            raise ValueError(
                "--device and --lvs are mutually exclusive arguments, choose one."
            )

        # Ensure to request the admin key early on.
        self._KEYSTORE.admin_key_for_input()

        if device:
            self._do_rekey(
                device=device,
                header=header,
                slot=slot,
            )
        else:
            candidates = run.json.lvs("-S", "lv_name=~\\-crypted$")
            for candidate in candidates:
                name = candidate["lv_name"].removesuffix("-crypted")
                if not fnmatch.fnmatch(name, lvs):
                    continue
                console.print(f"Replacing key for {name}")

                vg_name = candidate["vg_name"].replace("-", "--")
                lv_name_mapper = candidate["lv_name"].replace("-", "--")

                f"/dev/mapper/{vg_name}-{lv_name_mapper}"

                self._do_rekey(
                    slot=slot,
                    device=f"/dev/mapper/{vg_name}-{lv_name_mapper}",
                    header=header,
                )

        console.print("Key updated.", style="bold green")

    def _do_rekey(self, slot: str, device: str, header: Optional[str]):
        if slot == "local":
            # Rekey a new local key. Use the admin key for verifying.
            key_file_verification = "-"
            new_key_file = self._KEYSTORE.local_key_path()
            kill_input = add_input = self._KEYSTORE.admin_key_for_input()
        elif slot == "admin":
            key_file_verification = self._KEYSTORE.local_key_path()
            new_key_file = "-"
            kill_input = None
            add_input = self._KEYSTORE.admin_key_for_input()
        slot_id = self._KEYSTORE.slots[slot]

        header_arg = [f"--header={header}"] if header else []

        dump = run.cryptsetup("luksDump", *header_arg, device, encoding="ascii")
        if f"  {slot_id}: luks2" in dump:
            run.cryptsetup(
                "luksKillSlot",
                f"--key-file={key_file_verification}",
                *header_arg,
                device,
                slot_id,
                input=kill_input,
            )
        run.cryptsetup(
            "luksAddKey",
            f"--key-file={key_file_verification}",
            f"--key-slot={slot_id}",
            *header_arg,
            device,
            new_key_file,
            input=add_input,
        )

        if header:
            self._KEYSTORE.backup_external_header(Path(header))
