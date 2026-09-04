#!/usr/bin/env nix-shell
#! nix-shell -p uv -i "uv run --script"
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["rich", "pydantic"]
# ///

import ctypes
import getpass
import json
import os
import re
import subprocess
import sys
from contextlib import nullcontext
from dataclasses import dataclass
from email import message
from ipaddress import IPv6Address
from socket import gethostname
from typing import Any, ClassVar, TypeVar, override, reveal_type

from pydantic import (
    BaseModel,
    ConfigDict,
    IPvAnyAddress,
    TypeAdapter,
    model_validator,
)
from rich import print
from rich.markup import escape
from rich.prompt import Confirm, Prompt

# XXX: can we extract them somewhere from the platform?
RBD_POOLS = ["rbd.hdd", "rbd.ssd"]

V = TypeVar("V")


def plain(value: Any) -> Any:
    """Keep rich from swallowing `[...]` in data as console markup.

    Bracketed data is common here: IPv6 EntityAddrs (`[dead::1]:0/0`) and the
    repr'd argv in subprocess error messages. Only strings are affected, other
    objects go through rich's pretty printer untouched.
    """
    return escape(value) if isinstance(value, str) else value


# frozen to stay hashable, so imagespecs can be collected in sets
@dataclass(frozen=True)
class RbdImageSpec:
    pool: str
    imagename: str
    # in principle, snapshots are also part of an imagespec, but not relevant here

    @override
    def __str__(self) -> str:
        return f"{self.pool}/{self.imagename}"


class EntityAddr(BaseModel):
    # immutable by nature, and hashability allows collecting them in a set
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)

    # Ceph EntityAddrs look like `172.20.4.101:0/3733721661` or `[dead::1]:0/0`,
    # optionally prefixed with the messenger protocol version (`v1:`/`v2:`).
    ADDR_RE: ClassVar[re.Pattern[str]] = re.compile(
        r"""^
        (?:(?P<msgr_version>v[12]):)?
        (?:\[(?P<ip6>[0-9a-fA-F:.]+)\]|(?P<ip4>[0-9.]+))
        :(?P<port>\d+)
        /(?P<nonce>\d+)
        $""",
        re.VERBOSE,
    )

    # The original string is kept so it can be handed back to Ceph verbatim,
    # instead of risking a mismatch when re-formatting (IPv6 compression,
    # brackets, msgr version prefix).
    raw: str
    msgr_version: str | None = None
    ip: IPvAnyAddress
    port: int
    nonce: int

    @model_validator(mode="before")
    @classmethod
    def parse(cls, value: Any) -> Any:
        # Accept both the string form found in `rbd` output and an already
        # structured mapping.
        if not isinstance(value, str):
            return value
        match = cls.ADDR_RE.match(value)
        if not match:
            raise ValueError(f"not a Ceph EntityAddr: {value!r}")
        groups = match.groupdict()
        return {
            "raw": value,
            "msgr_version": groups["msgr_version"],
            "ip": groups["ip6"] or groups["ip4"],
            "port": groups["port"],
            "nonce": groups["nonce"],
        }

    @override
    def __str__(self) -> str:
        return self.raw


class RbdLock(BaseModel):
    id: str
    locker: str
    address: EntityAddr


class Ipmitool:
    # Implement mlock to avoid swapping as we store sensitive data (like encryption)
    # keys.
    # Constants defined by kernel, not dynamically accessible here:
    # https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/include/uapi/asm-generic/mman.h#n18

    MCL_CURRENT = 1
    MCL_FUTURE = 2

    hostname: str

    _ipmipw: str | None = None
    _ipmiuser: str | None = None

    libc = ctypes.CDLL("libc.so.6", use_errno=True)

    def __init__(self, hostname: str) -> None:
        self.hostname = hostname

    @classmethod
    def mlockall(cls) -> None:
        result = cls.libc.mlockall(cls.MCL_CURRENT | cls.MCL_FUTURE)
        if result != 0:
            raise Exception("cannot lock memory, errno=%s" % ctypes.get_errno())

    @property
    def ipmipw(self) -> str:
        if self._ipmipw is None:
            # allows clearing a wrong password by resetting the cached value to None
            self._ipmipw = getpass.getpass("IPMI access password: ")
        return self._ipmipw

    @property
    def ipmiuser(self) -> str:
        if self._ipmiuser is None:
            self._ipmiuser = input(f"IPMI user for {self.hostname}: ")
        return self._ipmiuser

    @property
    def env(self) -> dict[str, str]:
        # Passed via env (and fc-ipmitool's -E) rather than argv, so the
        # password doesn't show up in `ps`. Build a copy per call instead of
        # mutating os.environ, so it doesn't leak into unrelated subprocess
        # calls or outlive this invocation.
        return {**os.environ, "IPMI_PASSWORD": self.ipmipw}

    def __call__(
        self,
        *args: str,
        capture_output: bool = False,
        tty: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        cmd = ["fc-ipmitool", "-U", self.ipmiuser, self.hostname, *args]
        ctx = open("/dev/tty", "r+b", buffering=0) if tty else nullcontext()
        with ctx as f:
            return subprocess.run(
                cmd,
                stdin=f,
                stdout=f,
                stderr=f,
                capture_output=capture_output,
                text=True,
                errors="replace",
                encoding="utf-8",
                env=self.env,
            )


# XXX: replace with more robust subprocess call chain that cares about errors
class Rbd:
    ceph_client_name: str
    # for now assuming default ceph conf location, while fc.qemu handles this explicitly

    def __init__(self) -> None:
        self.ceph_client_name = f"client.{gethostname()}"

    def validate_json_cmd(self, tp: type[V], *args: Any, **kw: Any) -> V:
        # `tp` may be any type pydantic can validate: a BaseModel subclass just
        # as well as a plain container like `list[str]`.
        output = self.rbd_(*args, parse_json=False, **kw)
        return TypeAdapter(tp).validate_json(output)

    def pool_ls(self, pool: str) -> set[RbdImageSpec]:
        imgnames = self.validate_json_cmd(list[str], "ls", pool)
        return {RbdImageSpec(pool, imgname) for imgname in imgnames}

    def lock_ls(self, imgspec: RbdImageSpec) -> list[RbdLock]:
        return self.validate_json_cmd(list[RbdLock], "lock", "ls", str(imgspec))

    def rbd_(
        self,
        *args: str,
        use_json: bool = True,
        parse_json: bool = True,
        verbose=True,
    ) -> Any:
        format_arg = ["--format", "json"] if use_json else []
        cmd = ["rbd", "--name", self.ceph_client_name, *format_arg, *args]
        if verbose:
            print(cmd)
        result = subprocess.run(
            cmd, check=True, capture_output=True, text=True
        ).stdout
        if use_json and parse_json:
            result = json.loads(result)
        if verbose:
            print(plain(result))
        return result


def collect_image_locks(
    kvmhostname: str, rbd: Rbd
) -> dict[RbdImageSpec, list[RbdLock]]:
    # - tote VMs anhand von Ceph Lock identifizieren:
    host_locked_images: dict[RbdImageSpec, list[RbdLock]] = {}
    for pool in RBD_POOLS:
        # XXX: allow pool to not exist
        for imgspec in rbd.pool_ls(pool):
            # XXX non-atomic: handle image gone
            lockers = rbd.lock_ls(imgspec)
            # XXX: instead of assertion, collect as suspicious image to be investigated by operator later
            assert len(lockers) <= 1, (
                f"expected exclusive locking but got more than 1 lock {lockers}"
            )
            our_locks = [lock for lock in lockers if lock.id == kvmhostname]
            if our_locks:
                host_locked_images[imgspec] = our_locks

    return host_locked_images


# XXX: this can become a HostEvacuationTask class with a hostname property
def set_out_of_service(kvmhostname: str) -> None:
    # Setting a node permanently out of service is not possible via directory API for now
    print(
        f" > Set the host out of service in the directory: https://directory.fcio.net/machine/list?search=name-{kvmhostname}"
    )
    print()
    while not Confirm.ask(f"[purple]Is host {kvmhostname} set out-of-service?"):
        pass


def ensure_host_offline(
    kvmhostname: str,
) -> None:  # XXX: persist that the host has been set offline
    # - zuerst oneshot fc-ipmitool `power status`: wenn host klar down ist, dann können alle rbd locks aufgeräumt werden
    # XXX: retries?
    fc_ipmi = Ipmitool(kvmhostname)
    try:
        power_status = fc_ipmi(
            "power", "status", capture_output=True
        ).stdout.strip()

        if power_status == "Chassis Power is off":
            # we can force-unlock all the collected images
            return
    except subprocess.CalledProcessError as e:
        print(f"Error calling ipmitool: {escape(str(e))}")
    else:
        print(
            f"{kvmhostname} status is'{escape(power_status)}', please ensure it is not running any VMs before continuing."
        )
    # - falls nicht:
    while True:
        try:
            match Prompt.ask(
                "Do you want to connect to the [green]SOL[/green] console, open an ipmitool [green]shell[/green], or [green]continue[/green] anyway?",
                choices=["SOL", "shell", "continue"],
            ):
                # In practice, BMC connections can turn out to be rather flaky.
                # But retrying or deactivating-activating the SOL is left as a
                # task to the operator.
                case "SOL":
                    print(
                        "Opening a SOL console for your interactive investigations:"
                    )
                    _ = fc_ipmi("sol", "activate", tty=True)
                case "shell":
                    print("Opening an [i]ipmitool shell[/i]")
                    _ = fc_ipmi("shell", tty=True)
                case "continue":
                    print(
                        f"[yellow]If {kvmhostname} is not reliably down this may corrupt VM images. If there is any doubt, consider disconnecting the host from the Ceph cluster at network level."
                    )
                case _:
                    print("[orange]Invalid choice.")
                    continue
        except subprocess.CalledProcessError as e:
            print(escape(str(e)))
        if Confirm.ask(f"Did you ensure that {kvmhostname} is reliably down?"):
            break


def fmt_IPAddress(address: IPvAnyAddress) -> str:
    if isinstance(address, IPv6Address):
        return f"[{address}]"
    else:
        return str(address)


def main(kvmhostname: str):
    # XXX: support multiple KVM servers?
    # - zu Beginn: hostname des toten hosts angeben
    set_out_of_service(kvmhostname)

    ensure_host_offline(kvmhostname)

    rbd = Rbd()
    host_locked_images: dict[RbdImageSpec, list[RbdLock]] = collect_image_locks(
        kvmhostname, rbd
    )
    if not host_locked_images:
        print(
            f"Did not find any VM images locked by {kvmhostname}, nothing to rescue"
        )
        # XXX: host still out of service
        sys.exit(2)

    print(host_locked_images)

    locker_addresses: set[IPvAnyAddress] = {
        lockinfo.address.ip
        for lockers in host_locked_images.values()
        for lockinfo in lockers
        if lockinfo.id == kvmhostname
    }

    # By default, breaking a lock causes the address of the broken client
    # to be osd-blocklisted. We do want that, but with a larger blocklist
    # entry TTL, and for the full host. So adding that entry explicitly ahead of time.
    # 24h should be plenty enough to handle a broken host, but short enough
    # to recover in case we miss cleaning up the blocks.
    ceph_auth_id = gethostname()
    for locker_address in locker_addresses:
        _ = subprocess.run(
           [
            "ceph", "--id", ceph_auth_id,
            "osd", "blocklist", "add",
            # `<IPAddr>:0/0` is a special EntityAddr that covers all ports and nonces as well
            f"{fmt_IPAddress(locker_address)}:0/0", f"{24*60*60}"
           ],
           check=True,
           capture_output=True,
           text=True,
       )  # fmt: skip
        # XXX: print script on how to remove the blocklist entries later
    for img, lockers in host_locked_images.items():
        # XXX: error handling: locks can be gone, images might have changed
        # XXX: more than 1 lock: collect as a "something is weird" and alert operator afterwards
        if len(lockers) > 1:
            print(
                f"[orange]f{img} has multiple lockers. Will unlock all locks owned by {kvmhostname}, but please check afterwards."
            )
            # XXX: add to
        my_locks = [
            lockinfo for lockinfo in lockers if lockinfo.id == kvmhostname
        ]
        # XXX: id != kvmhostname: skip, collect as a "something is weird" and alert operator afterwards
        for lockinfo in lockers:
            if lockinfo.id != kvmhostname:
                print(
                    f"[orange]{img} is also locked by {lockinfo.id}. Skipping the unlock, please check afterwards."
                )
                continue

            _ = rbd.rbd_(
                "lock",
                "remove",
                "--rbd_blocklist_on_break_lock=false",
                str(img),
                lockinfo.id,
                lockinfo.locker,
                use_json=False,
            )

    # - finally evacuate all VMs away
    subprocess.run(["fc-directory", f"d.evacuate_vms('{kvmhostname}')"], check=True)  # fmt: skip


if __name__ == "__main__":
    main(sys.argv[1])
