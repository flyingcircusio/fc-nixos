import fnmatch
import getpass
import hashlib
import os
import secrets
import shutil
from pathlib import Path
from subprocess import CalledProcessError
from typing import NamedTuple, Optional

from fc.ceph.luks import KEYSTORE  # singleton
from fc.ceph.luks import Cryptsetup
from fc.ceph.luks.checks import all_checks
from fc.ceph.lvm import XFSVolume
from fc.ceph.util import console, run


class LuksDevice(NamedTuple):
    base_blockdev: str  # path of the underlying block device
    name: str  # the LUKS name of the device
    # required for external header discovery, which we only utilise for backy
    mountpoint: Optional[str]
    header: Optional[str] = None

    @classmethod
    def lsblk_to_cryptdevices(cls, lsblk_blockdevs: list) -> list["LuksDevice"]:
        """parses the output of lsblk -Js -o NAME,PATH,TYPE,MOUNTPOINT"""
        return [
            cls(
                base_blockdev=dev["children"][0]["path"],
                name=dev["name"],
                mountpoint=dev["mountpoint"],
            )
            for dev in lsblk_blockdevs
            if dev["type"] == "crypt"
        ]

    @classmethod
    def filter_cryptvolumes(
        cls, name_glob: str, header: Optional[str]
    ) -> list["LuksDevice"]:
        """Retrieves visible crypt volumes via `lsblk`, filters their name to
        match `name_glob`.

        Optionally takes a path to an external `header` file, otherwise does
        auto-discovery based on looking for a corresponding header file named
        <mountpoint>.luks and passes an Optional[str].
        """
        candidates = cls.lsblk_to_cryptdevices(
            run.json.lsblk("-s", "-o", "NAME,PATH,TYPE,MOUNTPOINT")
        )

        matching_devs = []
        for candidate in candidates:
            if not fnmatch.fnmatch(candidate.name, name_glob):
                continue

            # adjust headers with autodetected heuristics
            if (
                (not header)
                and (mp := candidate.mountpoint)
                and os.path.exists(headerfile := f"{mp}.luks")
            ):
                matching_devs.append(candidate._replace(header=headerfile))
            else:
                matching_devs.append(candidate._replace(header=header))

        if header and (match_count := len(matching_devs)) > 1:
            raise ValueError(
                f"Got {match_count} matching devices for glob '{name_glob}'.\n"
                "When specifying an external header file, the target device "
                "needs to be a single specific match."
            )

        return matching_devs


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

        for dev in LuksDevice.filter_cryptvolumes(name_glob, header=header):
            console.print(f"Rekeying {dev.name}")
            self._do_rekey(slot, device=dev.base_blockdev, header=dev.header)

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

    @staticmethod
    def check_luks(name_glob: str, header: Optional[str]) -> int:
        devices = LuksDevice.filter_cryptvolumes(name_glob, header=header)
        if not devices:
            console.print(
                f"Warning: The glob `{name_glob}` matches no volume.",
                style="yellow",
            )
            return 1

        errors = 0
        for dev in devices:
            console.print(f"Checking {dev.name}:")
            dump_lines = (
                Cryptsetup.cryptsetup("luksDump", dev.base_blockdev)
                .decode("utf-8")
                .splitlines()
            )
            for check in all_checks:
                check_ok = True
                for error in check(dump_lines):
                    errors += 1
                    check_ok = False
                    console.print(f"{check.__name__}: {error}", style="red")
                if check_ok:
                    console.print(f"{check.__name__}: OK", style="green")

        return 1 if errors else 0

    def test_open(self, name_glob: str, header: Optional[str]) -> int:
        # Ensure to request the admin key early on.
        self._KEYSTORE.admin_key_for_input()

        devices = LuksDevice.filter_cryptvolumes(name_glob, header=header)
        if not devices:
            console.print(
                f"Warning: The glob `{name_glob}` matches no volume.",
                style="yellow",
            )
            return 1

        failing_devices = []
        for dev in devices:
            console.print(f"Test opening {dev.name}")
            if not self._do_test_open(dev.base_blockdev, header=dev.header):
                failing_devices.append(dev)

        if failing_devices:
            console.print(
                "The following devices failed to open:\n"
                + (
                    "\n".join(
                        (
                            f"{dev.base_blockdev} ({dev.name})"
                            for dev in failing_devices
                        )
                    )
                ),
                style="red",
            )
            return 2

        return 0

    def _do_test_open(self, device: str, header: Optional[str]) -> bool:
        header_arg = [f"--header={header}"] if header else []
        success = True

        # test unlocking both with local key file as well as with admin key
        try:
            test_admin = Cryptsetup.cryptsetup(
                "open",
                "--test-passphrase",
                device,
                input=self._KEYSTORE.admin_key_for_input(),
            )
        except CalledProcessError:
            console.print(
                f"Failed to open {device} with admin passphrase.", style="red"
            )
            success = False
        try:
            test_local = Cryptsetup.cryptsetup(
                "open",
                "--test-passphrase",
                f"--key-file={self._KEYSTORE.local_key_path()}",
                device,
            )
        except CalledProcessError:
            console.print(
                f"Failed to open {device} with local key file.", style="red"
            )
            success = False

        return success

        if header:
            self._KEYSTORE.backup_external_header(Path(header))

    def fingerprint(self, verify: bool, confirm: bool) -> int:
        """
        Ask for passphrase and print its fingerprint.

        For `verify`, compare with stored fingerprint and return a status code
        1 at mismatch"""

        while True:
            input_phrase = getpass.getpass("Enter passphrase to fingerprint: ")
            if not confirm:
                break
            if getpass.getpass("Confirm passphrase again: ") == input_phrase:
                break
            print("Mismatching passphrases entered, please retry.")

        fingerprint = hashlib.sha256(input_phrase.encode("ascii")).hexdigest()
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
