import asyncio
import getpass
import hashlib
import os
import shlex
import shutil
from functools import wraps
from pathlib import Path
from socket import gethostname
from subprocess import CalledProcessError
from typing import Optional

from fc.ceph.util import console, mlockall, prompt_bool, run


def memoize(func):
    """Caches the result of a memeber method invocation in an attribute of the
    called function name prefixed with '__'
    """

    @wraps(func)
    def wrapper(self, *args, **kw):
        attr_name = "__" + func.__name__
        if not hasattr(self, attr_name):
            setattr(self, attr_name, func(self, *args, **kw))
        return getattr(self, attr_name)

    return wrapper


class LUKSKeyStore(object):
    slots = {"admin": "1", "local": "0"}
    local_key_dir: Path = Path("/mnt/keys/")

    def __init__(self):
        # Ensure we're locking memory early to reduce risk
        mlockall()

    def local_key_path(self) -> str:
        return str(self.local_key_dir / f"{gethostname()}.key")

    @memoize
    def admin_key_for_input(
        self, prompt: str = "LUKS admin key for this location"
    ) -> bytes:
        while True:
            admin_key = getpass.getpass(f"{prompt}: ").encode("ascii")

            fingerprint_path = self.local_key_dir / "admin.fprint"
            persisted_fingerprint: str = ""
            if fingerprint_path.exists():
                persisted_fingerprint = (
                    open(fingerprint_path, "rt").read().strip()
                )

            fingerprint = hashlib.sha256(admin_key).hexdigest()

            if fingerprint == persisted_fingerprint:
                break

            if not persisted_fingerprint:
                console.print("No admin key fingerprint stored.\n")
            else:
                console.print(
                    "Error: fingerprint mismatch:\n\n"
                    f"fingerprint for your entry: '{fingerprint}'\n"
                    f"fingerprint stored locally: '{persisted_fingerprint}'\n"
                )

            if not prompt_bool(
                f"Is '{fingerprint}' the correct new fingerprint?\nRetry otherwise.",
                default=False,
            ):
                console.print("Retrying.")
                continue

            console.print(
                f"Updating persisted fingerprint to {fingerprint_path!s}"
            )

            with open(fingerprint_path, "wt") as f:
                f.write(fingerprint)
            break

        console.print(
            f"Using admin key with matching fingerprint '{fingerprint}'."
        )
        return admin_key

    def backup_external_header(self, headerfile: Path):
        # assumption: all external volume headers of a machine have distinct names
        shutil.copy(headerfile, self.local_key_dir)


class Cryptsetup:
    """
    Opinionated method wrapper around cryptsetup in general and some of its
    methods in particular.
    Useful to ensure that certain default tunable parameters are applied.
    """

    cryptsetup_tunables = [
        # inspired by the measurements done in https://ceph.io/en/news/blog/2023/ceph-encryption-performance/:
        "--perf-submit_from_crypt_cpus",
        # for larger writes throughput
        # might be useful as well and is discussed to be enabled in Ceph,
        # but requires kernel >=5.9: https://github.com/ceph/ceph/pull/49554
        # especially relevant for SSDs, see https://blog.cloudflare.com/speeding-up-linux-disk-encryption/
        # "--perf-no_read_workqueue", "--perf-no_write_workqueue"
    ]  # fmt: skip
    # reduce CPU load for larger writes, can be removed after cryptsetup >=2.40
    _tunables_sectorsize = ("--sector-size", "4096")

    # tunables that aspply when (re)creating a LUKS volume and its data or reencrypting it
    _tunables_cipher = (
        "--cipher", "aes-xts-plain64",
        "--key-size", "512",
    )  # fmt: skip
    # tunables that apply when (re)creating a LUKS volume header
    _tunables_luks_header = (
        "--pbkdf", "argon2id",
        "--type", "luks2",
    )  # fmt: skip

    @classmethod
    def cryptsetup(cls, *args: str, **kwargs):
        """cryptsetup wrapper that adds default tunable options to the calls"""
        return run.cryptsetup("-q", *cls.cryptsetup_tunables, *args, **kwargs)

    @classmethod
    def luksFormat(cls, *args: str, **kwargs):
        return cls.cryptsetup(
            *cls._tunables_sectorsize,
            *cls._tunables_luks_header,
            *cls._tunables_cipher,
            "luksFormat",
            *args, **kwargs,
        )  # fmt: skip

    @classmethod
    def luksAddKey(cls, *args: str, **kwargs):
        return cls.cryptsetup(
            *cls._tunables_luks_header,
            *cls._tunables_cipher,
            "luksAddKey",
            *args, **kwargs,
        )  # fmt: skip

    @classmethod
    async def cryptsetup_async(
        cls, *args: str, input: Optional[bytes] = None, check: bool = True
    ) -> bytes:
        """`cryptsetup` wrapper for coroutines.

        Runs the command without blocking the event loop, so that several
        volumes can be rekeyed concurrently.
        """
        argv = ("cryptsetup", "-q", *cls.cryptsetup_tunables, *args)
        console.print("$", argv[0], shlex.join(argv[1:]), style="grey50")
        proc = await asyncio.create_subprocess_exec(
            *argv,
            stdin=(
                asyncio.subprocess.PIPE
                if input is not None
                else asyncio.subprocess.DEVNULL
            ),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await proc.communicate(input)
        if proc.returncode:
            console.print(f"> return code: {proc.returncode}", style="red")
            console.print("> stdout:", style="red")
            console.print(stdout.decode("ascii", errors="replace"), style="red")
            console.print("> stderr:", style="red")
            console.print(stderr.decode("ascii", errors="replace"), style="red")
            if check:
                raise CalledProcessError(proc.returncode, argv, stdout, stderr)
        return stdout


KEYSTORE = LUKSKeyStore()
