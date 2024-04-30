import fnmatch
import getpass
import hashlib
import os
import secrets
import shutil
from pathlib import Path
from typing import NamedTuple, Optional

from fc.ceph.luks import KEYSTORE  # singleton
from fc.ceph.lvm import XFSVolume
from fc.ceph.util import console, run


class LuksDevice(NamedTuple):
    base_blockdev: str  # path of the underlying block device
    name: str  # the LUKS name of the device
    # required for external header discovery, which we only utilise for backy
    mountpoint: Optional[str]


# TODO: better typing signature
# Todo: should this be a static class method instead?
def lsblk_to_cryptdevices(lsblk_blockdevs: list) -> list:
    """parses the output of lsblk -Js -o NAME,PATH,TYPE,MOUNTPOINT"""
    return [
        LuksDevice(
            base_blockdev=dev["children"][0]["path"],
            name=dev["name"],
            mountpoint=dev["mountpoint"],
        )
        for dev in lsblk_blockdevs
        if dev["type"] == "crypt"
    ]


class LUKSKeyStoreManager(object):
    def __init__(self):
        self.volume = XFSVolume("keys", "/mnt/keys", automount=True)
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
        name_glob: str,
        header: Optional[str],
        slot="local",
    ):
        """Update keyslots, using the opposite key for assurance."""

        if slot == "local":
            console.print("Updating local machine key ...", style="bold")
            # Ensure to request the admin key early on.
            self._KEYSTORE.admin_key_for_input(
                "Current LUKS admin key for unlocking this location"
            )
        elif slot == "admin":
            console.print("Updating admin key ...", style="bold")
            # Ensure to request the admin key early on.
            self._KEYSTORE.admin_key_for_input(
                "New LUKS admin key to be set for this location"
            )
        else:
            raise ValueError(f"slot={slot}")

        candidates = lsblk_to_cryptdevices(
            run.json.lsblk("-s", "-o", "NAME,PATH,TYPE,MOUNTPOINT")
        )
        for candidate in candidates:
            this_header = header
            if not fnmatch.fnmatch(candidate.name, name_glob):
                continue
            console.print(f"Replacing key for {candidate.name}")

            if (
                (not this_header)
                and (mp := candidate.mountpoint)
                and os.path.exists(headerfile := f"{mp}.luks")
            ):
                this_header = headerfile
            self._do_rekey(
                slot=slot,
                device=candidate.base_blockdev,
                header=this_header,
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

    def fingerprint(self, verify: bool, confirm: bool) -> int:
        """
        Ask for passphrase and print its fingerprint.

        For `verify`, compare with stored fingerprint and return a status code
        1 at mismatch"""

        input_phrase: Optional[bytes] = None

        while not input_phrase:
            input_phrase = getpass.getpass(
                "Enter passphrase to fingerprint: "
            ).encode("ascii")
            if (
                confirm
                and getpass.getpass("Confirm passphrase again: ").encode(
                    "ascii"
                )
                != input_phrase
            ):
                print("Mismatching passphrases entered, please retry.")
                input_phrase = None

        fingerprint = hashlib.sha256(input_phrase).hexdigest()
        console.print(fingerprint)

        if verify:
            fingerprint_path = self._KEYSTORE.local_key_dir / "admin.fprint"
            persisted_fingerprint = (
                open(fingerprint_path, "rt").read().strip()
                if fingerprint_path.exists()
                else ""
            )
            if not persisted_fingerprint:
                console.print("No admin key fingerprint stored.\n")
                return 1
            elif persisted_fingerprint != fingerprint:
                console.print(
                    "Error: fingerprint mismatch:\n\n"
                    f"fingerprint for your entry: '{fingerprint}'\n"
                    f"fingerprint stored locally: '{persisted_fingerprint}'\n"
                )
                return 1

        return 0
