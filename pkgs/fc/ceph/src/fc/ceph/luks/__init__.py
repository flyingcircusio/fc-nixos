import getpass
import shutil
from pathlib import Path
from socket import gethostname

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


class Cryptsetup:
    """
    Opinionated method wrapper around cryptsetup in general and some of its
    methods in particular.
    Useful to ensure that certain default tunable parameters are applied.
    """

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
        return run.cryptsetup("-q", *cls.cryptsetup_tunables, *args, **kwargs)

    @classmethod
    def luksFormat(cls, *args: str, **kwargs):
        return cls.cryptsetup(
            # fmt: off
            *cls._tunables_sectorsize,
            *cls._tunables_luks_header,
            *cls._tunables_cipher,
            "luksFormat",
            *args, **kwargs,
            # fmt: on
        )

    @classmethod
    def luksAddKey(cls, *args: str, **kwargs):
        return cls.cryptsetup(
            # fmt: off
            *cls._tunables_luks_header,
            "luksAddKey",
            *args, **kwargs,
            # fmt: on
        )


KEYSTORE = LUKSKeyStore()
