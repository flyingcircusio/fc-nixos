import fnmatch
import getpass
import secrets
import shutil
from pathlib import Path
from socket import gethostname

from fc.ceph.lvm import XFSCephVolume
from fc.ceph.util import console, mlockall, run


def get_password(prompt):
    pw1 = pw2 = None
    while not pw1:
        pw1 = getpass.getpass(f"{prompt}: ")
        pw2 = getpass.getpass(f"{prompt}, repeated: ")
        if pw1 != pw2:
            console.print("Keys do not match. Try again.", style="red")
            pw1 = pw2 = None
    return pw1


class LUKSKeyStoreManager(object):
    def __init__(self):
        self.volume = XFSCephVolume("keys", "/mnt/keys", automount=True)

    def create(self, device):
        console.print(f"Creating keystore on {device} ...", style="bold")
        self.volume.create("vgkeys", "1g", device)
        console.print(
            f"Creating secret key in {KEYSTORE.local_key_path()} ...",
            style="bold",
        )

        keyfile = Path(KEYSTORE.local_key_path())
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

    def rekey(self, lvs="*", slot="local"):
        """Update keyslots, using the opposite key for assurance."""

        if slot == "local":
            console.print("Updating local machine key ...", style="bold")
        elif slot == "admin":
            console.print("Updating admin key ...", style="bold")
        else:
            raise ValueError(f"slot={slot}")

        # Ensure to request the admin key early on.
        KEYSTORE.admin_key_for_input()

        candidates = run.json.lvs("-S", "lv_name=~\\-crypted$")
        for candidate in candidates:
            name = candidate["lv_name"].removesuffix("-crypted")
            if not fnmatch.fnmatch(name, lvs):
                continue
            console.print(f"Replacing key for {name}")

            vg_name = candidate["vg_name"].replace("-", "--")
            lv_name_mapper = candidate["lv_name"].replace("-", "--")

            device = f"/dev/mapper/{vg_name}-{lv_name_mapper}"

            if slot == "local":
                # Rekey a new local key. Use the admin key for verifying.
                key_file_verification = "-"
                new_key_file = KEYSTORE.local_key_path()
                kill_input = add_input = KEYSTORE.admin_key_for_input()
            elif slot == "admin":
                key_file_verification = KEYSTORE.local_key_path()
                new_key_file = "-"
                kill_input = None
                add_input = KEYSTORE.admin_key_for_input()
            slot_id = KEYSTORE.slots[slot]

            dump = run.cryptsetup("luksDump", device, encoding="ascii")
            if f"  {slot_id}: luks2" in dump:
                run.cryptsetup(
                    "luksKillSlot",
                    f"--key-file={key_file_verification}",
                    device,
                    slot_id,
                    input=kill_input,
                )
            run.cryptsetup(
                "luksAddKey",
                f"--key-file={key_file_verification}",
                f"--key-slot={slot_id}",
                device,
                new_key_file,
                input=add_input,
            )

        console.print("Key updated.", style="bold green")


class LUKSKeyStore(object):
    __admin_key = None

    slots = {"admin": "1", "local": "0"}

    def __init__(self):
        # Ensure we're locking memory early to reduce risk
        mlockall()

    def local_key_path(self):
        return f"/mnt/keys/{gethostname()}.key"

    def admin_key_for_input(self):
        if not self.__admin_key:
            self.__admin_key = get_password("LUKS admin key for this location")
        return self.__admin_key.encode("ascii")


KEYSTORE = LUKSKeyStore()
