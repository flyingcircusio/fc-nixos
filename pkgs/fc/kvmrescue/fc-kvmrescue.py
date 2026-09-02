#!/usr/bin/env nix-shell
#! nix-shell -p uv -i "uv run --script"
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["rich"]
# ///

import ctypes
import getpass
import json
import os
import subprocess
import sys
from contextlib import nullcontext
from email import message
from socket import gethostname
from typing import Any, reveal_type

from rich import print
from rich.prompt import Confirm, Prompt

# XXX: can we extract them somewhere from the platform?
RBD_POOLS = ["rbd.hdd", "rbd.ssd"]


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


# XXX: replace with more robust subprocess call chain that cares about errors, as in fc.qemu or fc-ceph
class Rbd:
    ceph_client_name: str
    # for now assuming default ceph conf location, while fc.qemu handles this explicitly

    def __init__(self) -> None:
        self.ceph_client_name = f"client.{gethostname()}"

    def rbd_(self, *args: str, use_json: bool = True, verbose=True) -> Any:
        format_arg = ["--format", "json"] if use_json else []
        cmd = ["rbd", "--name", self.ceph_client_name, *format_arg, *args]
        if verbose:
            print(cmd)
        result = subprocess.run(
            cmd, check=True, capture_output=True, text=True
        ).stdout
        if use_json:
            result = json.loads(result)
        if verbose:
            print(result)
        return result


def collect_image_locks(kvmhostname: str, rbd: Rbd) -> list[str]:
    # - tote VMs anhand von Ceph Lock identifizieren:
    # XXX: alternative: we could try querying the active keepalives via the pysensu API directly from Sensu. But this
    # - introduces another dependency on Sensu
    # - requires pulling in pysensu
    # - VM keepalive timeout is currently slightly higher for hosts than VMs
    # - advantage though: might be more performant than iterating over _all_ the rbd images of the cluster
    host_locked_images: list[str] = []
    for pool in RBD_POOLS:
        # XXX: consider speeding up by parallelising calls, bounded by an asyncio Semaphor
        # XXX: allow pool to not exist
        all_images = rbd.rbd_("ls", pool)
        for image in all_images:
            # XXX non-atomic: handle image gone
            imgspec = f"{pool}/{image}"
            lockers = rbd.rbd_("lock", "ls", imgspec)
            assert len(lockers) <= 1, (
                f"expected exclusive locking but got more than 1 lock {lockers}"
            )
            if any((True for lock in lockers if lock["id"] == kvmhostname)):
                host_locked_images.append(imgspec)

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
            return True
    except subprocess.CalledProcessError as e:
        print(f"Error calling ipmitool: {e}")
    else:
        print(
            f"{kvmhostname} status is'{power_status}', please ensure it is not running any VMs before continuing."
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
            print(e)
        if Confirm.ask(f"Did you ensure that {kvmhostname} is reliably down?"):
            break


def main(kvmhostname: str):
    # XXX: support multiple KVM servers?
    # - zu Beginn: hostname des toten hosts angeben
    set_out_of_service(kvmhostname)

    rbd = Rbd()
    host_locked_images = collect_image_locks(kvmhostname, rbd)
    if not host_locked_images:
        print(
            f"Did not find any VM images locked by {kvmhostname}, nothing to rescue"
        )
        # XXX: host still out of service
        sys.exit(2)

    print(host_locked_images)

    safe_to_unlock = ensure_host_offline(kvmhostname)

    if not safe_to_unlock:
        _ = input(
            f"About to force-unlock all VMs of {kvmhostname}, ensure host is down! [Enter to confirm]"
        )
    # Track EntityAddrs of lockers. We do not yet make use of them, but they might be useful when migrating to exclusive-lock PL-134255
    locker_addresses = set[str]()
    for img in host_locked_images:
        # XXX: error handling: locks can be gone, images might have changed
        lockinfo = rbd.rbd_("lock", "ls", img)[0]
        locker_address = lockinfo["address"]
        locker_addresses.add(locker_address)

        # By default, breaking a lock causes the address of the broken client
        # to be osd-blocklisted. We do want that, but with a larger blocklist
        # entry TTL, so adding that entry explicitly ahead of time.
        # 24h should be plenty enough to handle a broken host, but short enough
        # to not having to clear up the entry manually.
        _ = subprocess.run(
            ["ceph", "osd", "blocklist", "add", locker_address, f"{24*60*60}"],
            check=True,
            capture_output=True,
            text=True,
        )  # fmt: skip
        _ = rbd.rbd_(
            "lock",
            "remove",
            "--rbd_blocklist_on_break_lock=false",
            img,
            lockinfo["id"],
            lockinfo["locker"],
            use_json=False,
        )
        # XXX: more than 1 lock: collect as a "something is weird" and alert operator afterwards
        # XXX: id != kvmhostname: skip, collect as a "something is weird" and alert operator afterwards

    # - finally evacuate all VMs away
    subprocess.run(["fc-directory", f"d.evacuate_vms('{kvmhostname}')"], check=True)  # fmt: skip


if __name__ == "__main__":
    main(sys.argv[1])
