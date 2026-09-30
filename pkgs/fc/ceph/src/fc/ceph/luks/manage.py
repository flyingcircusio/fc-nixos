import asyncio
import fnmatch
import getpass
import hashlib
import os
import secrets
import shutil
from pathlib import Path
from subprocess import CalledProcessError
from typing import NamedTuple, Optional

from fc.ceph.luks import (
    KEYSTORE,  # singleton
    Cryptsetup,
)
from fc.ceph.luks.checks import all_checks
from fc.ceph.lvm import EncryptedLogicalVolume, XFSVolume
from fc.ceph.util import console, run
from rich.progress import Progress


def _cpu_count() -> int:
    # fc-ceph is on Python 3.12: os.process_cpu_count (3.13+) would respect
    # cgroups and CPU affinity.
    return os.cpu_count() or 1


def default_parallelism() -> int:
    return max(1, _cpu_count() // 2)


async def run_parallel(
    items: list, jobs, label: str, workers: int
) -> list[str]:
    """Run `jobs(item)` for every item, at most `workers` of them at a time.

    Shows a progress bar, reports failures as they happen and returns the
    names of the items that failed.
    """
    semaphore = asyncio.Semaphore(max(1, workers))
    with Progress() as progress:
        bar = progress.add_task(label, total=len(items))

        async def run(item):
            async with semaphore:
                console.print(f"{label} {item.name} ...")
                try:
                    await jobs(item)
                except Exception as e:
                    console.print(
                        f"{label} {item.name} failed: {e}", style="bold red"
                    )
                    raise
                finally:
                    progress.advance(bar)

        results = await asyncio.gather(
            *(run(item) for item in items), return_exceptions=True
        )

    return [
        item.name
        for item, result in zip(items, results)
        if isinstance(result, BaseException)
    ]


class LuksDevice(NamedTuple):
    base_blockdev: str  # path of the underlying block device
    base_blockdev_name: str  # name of the underlying block device
    luks_name: Optional[str] = None  # the LUKS name of the device
    # required for external header discovery, which we only utilise for backy
    mountpoint: Optional[str] = None
    header: Optional[str] = None

    @property
    def name(self) -> str:
        """Often we just need *any* name to filter on or display, let's take
        the best we can get."""
        return self.luks_name if self.luks_name else self.base_blockdev_name

    @classmethod
    def detect_cryptdevices(
        cls, lsblk_blockdevs: list, only_active: bool
    ) -> list["LuksDevice"]:
        """Detects crypt devices from lsblk -Js -o NAME,PATH,TYPE,MOUNTPOINT output.

        When only_active is False, also probes LVM volumes via
        `cryptsetup isLuks` to find inactive LUKS devices."""

        devs = []
        for dev in lsblk_blockdevs:
            # In the json output, we are only interested in the top-level list entries.
            # These represent the leaf-node devices, meaning the most concrete
            # device subsystem possible.
            if dev["type"] == "crypt":
                devs.append(
                    cls(
                        base_blockdev=dev["children"][0]["path"],
                        base_blockdev_name=dev["children"][0]["name"],
                        luks_name=dev["name"],
                        mountpoint=dev["mountpoint"],
                    )
                )
                # crypt devices' base blockdevs only show up in their children,
                # not again in the top-level list. We're done here.
                continue
            if dev["type"] == "lvm" and not only_active:
                try:
                    run.cryptsetup("isLuks", dev["path"], check=True)
                except CalledProcessError as e:
                    if e.returncode == 1:
                        # not a luks device
                        continue
                    else:
                        raise
                else:
                    # is a luks device
                    devs.append(
                        cls(
                            base_blockdev=dev["path"],
                            base_blockdev_name=dev["name"],
                        )
                    )

        return devs

    @classmethod
    def filter_cryptvolumes(
        cls, name_glob: str, only_active: bool, header: Optional[str]
    ) -> list["LuksDevice"]:
        """Retrieves visible crypt volumes via `lsblk`, filters their name to
        match `name_glob`.

        Optionally takes a path to an external `header` file, otherwise does
        auto-discovery based on looking for a corresponding header file named
        <mountpoint>.luks and passes an Optional[str].
        """
        candidates = cls.detect_cryptdevices(
            run.json.lsblk("-s", "-o", "NAME,PATH,TYPE,MOUNTPOINT"),
            only_active=only_active,
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
            f"Destroying keystore in {self.volume.mountpoint} ...",
            style="bold",
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
        only_active: bool,
        header: Optional[str],
        parallel: int,
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

        devices = LuksDevice.filter_cryptvolumes(
            name_glob, only_active=only_active, header=header
        )

        async def rekey(dev: LuksDevice):
            await self._do_rekey(
                slot, device=dev.base_blockdev, header=dev.header
            )

        failures = asyncio.run(
            run_parallel(devices, rekey, "Rekeying", parallel)
        )

        if failures:
            console.print(
                "Rekeying failed for: " + ", ".join(failures), style="bold red"
            )
            return 1

        console.print("Key updated.", style="bold green")
        return 0

    async def _do_rekey(
        self,
        slot: str,
        device: str,
        header: Optional[str],
    ):
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

        header_arg = ["--header", header] if header else []

        dump = await Cryptsetup.cryptsetup_async(
            "luksDump", *header_arg, device, encoding="ascii"
        )
        if f"  {slot_id}: luks2" in dump:
            await Cryptsetup.cryptsetup_async(
                "luksKillSlot",
                f"--key-file={key_file_verification}",
                *header_arg,
                device,
                slot_id,
                input=kill_input,
            )
        await Cryptsetup.cryptsetup_async(
            "luksAddKey",
            f"--key-file={key_file_verification}",
            f"--key-slot={slot_id}",
            *header_arg,
            *Cryptsetup._tunables_luks_header,
            *Cryptsetup._tunables_cipher,
            device,
            new_key_file,
            input=add_input,
        )

        if header:
            self._KEYSTORE.backup_external_header(Path(header))

    @staticmethod
    def check_luks(
        name_glob: str, only_active: bool, header: Optional[str]
    ) -> int:
        devices = LuksDevice.filter_cryptvolumes(
            name_glob, only_active=only_active, header=header
        )
        if not devices:
            console.print(f"Note: The glob `{name_glob}` matches no volume.")
            # Do not fail as hosts may be prepared for encryption without having
            # any encrypted volume yet.

        errors = 0
        for dev in devices:
            console.print(f"Checking {dev.name}:")
            if dev.header:
                luks_dump = Cryptsetup.cryptsetup(
                    "luksDump", "--header", dev.header, dev.base_blockdev
                )
            else:
                luks_dump = Cryptsetup.cryptsetup("luksDump", dev.base_blockdev)
            dump_lines = luks_dump.decode("utf-8").splitlines()
            for check in all_checks:
                check_ok = True
                for error in check(dump_lines, header=dev.header):
                    errors += 1
                    check_ok = False
                    console.print(f"{check.__name__}: {error}", style="red")
                if check_ok:
                    console.print(f"{check.__name__}: OK", style="green")

        return 1 if errors else 0

    def test_open(
        self, name_glob: str, only_active: bool, header: Optional[str]
    ) -> int:
        # Ensure to request the admin key early on.
        self._KEYSTORE.admin_key_for_input()

        devices = LuksDevice.filter_cryptvolumes(
            name_glob, only_active=only_active, header=header
        )
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
        header_arg = ["--header", header] if header else []
        success = True

        # test unlocking both with local key file as well as with admin key
        try:
            Cryptsetup.cryptsetup(
                "open",
                *header_arg,
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
            Cryptsetup.cryptsetup(
                "open",
                *header_arg,
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

    def unlock(self, name_glob: str, parallel: int) -> int:
        """Unlock matching volumes with the admin key, asking for it once."""
        self._KEYSTORE.admin_key_for_input(
            "LUKS admin key for unlocking volumes at this location"
        )

        matching = EncryptedLogicalVolume.matching(name_glob)
        locked = []
        for volume in matching:
            if volume.is_unlocked():
                console.print(f"{volume.name} is already unlocked, skipping.")
            else:
                locked.append(volume)

        if not locked:
            if matching:
                console.print(
                    f"Note: All volumes matching `{name_glob}` are already "
                    "unlocked."
                )
            else:
                console.print(
                    f"Note: The glob `{name_glob}` matches no volume."
                )
            return 0

        async def unlock(volume: EncryptedLogicalVolume):
            await volume.activate_async(self._KEYSTORE.admin_key_for_input())

        failures = asyncio.run(
            run_parallel(locked, unlock, "Unlocking", parallel)
        )

        if failures:
            console.print(
                "Unlocking failed for: " + ", ".join(failures),
                style="bold red",
            )
            return 1

        console.print("Volumes unlocked.", style="bold green")
        return 0

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
