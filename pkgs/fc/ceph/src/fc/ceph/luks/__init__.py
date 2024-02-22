import getpass
import shutil
from pathlib import Path
from socket import gethostname

from fc.ceph.util import console, mlockall


def get_password(prompt):
    pw1 = pw2 = None
    while not pw1:
        pw1 = getpass.getpass(f"{prompt}: ")
        pw2 = getpass.getpass(f"{prompt}, repeated: ")
        if pw1 != pw2:
            console.print("Keys do not match. Try again.", style="red")
            pw1 = pw2 = None
    return pw1


class LUKSKeyStore(object):
    __admin_key = None

    slots = {"admin": "1", "local": "0"}
    local_key_dir: Path = Path("/mnt/keys/")

    def __init__(self):
        # Ensure we're locking memory early to reduce risk
        mlockall()

    def local_key_path(self) -> str:
        return str(self.local_key_dir / f"{gethostname()}.key")

    def admin_key_for_input(self) -> str:
        if not self.__admin_key:
            self.__admin_key = get_password("LUKS admin key for this location")
        return self.__admin_key.encode("ascii")

    def backup_external_header(self, headerfile: Path):
        # assumption: all external volume headers of a mchine have distinct names
        shutil.copy(headerfile, self.local_key_dir)


KEYSTORE = LUKSKeyStore()
