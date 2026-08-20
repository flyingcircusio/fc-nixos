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
from socket import gethostname
from typing import Any, reveal_type

import rich

# XXX: can we extract them somewhere from the platform?
RBD_POOLS = ["rbd.hdd", "rbd.ssd"]


def prompt_y_n_x(
    msg: str, default: bool, extra_choices: list[tuple[str, str]] | None = None
) -> bool | str:
    extra_keys = {abbrev for abbrev, _ in extra_choices or []}
    choice: bool | str = default
    prompt = "[y]/n:" if default else "y/[n]:"
    if extra_choices:
        prompt += (
            " (" + ", ".join(f"{k}={desc}" for k, desc in extra_choices) + ")"
        )
    print(msg, prompt, end=" ")
    while True:
        resp = input()
        match resp:
            case "n":
                choice = False
                break
            case "y":
                choice = True
                break
            case "":
                choice = default
                break
            case key if key in extra_keys:
                choice = key
                break
            case _:
                print(f"Invalid input '{resp}', retry.")
                continue
    return choice


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
        capture_output=False,
    ) -> subprocess.CompletedProcess[str]:
        cmd = ["fc-ipmitool", "-U", self.ipmiuser, self.hostname, *args]
        return subprocess.run(
            cmd,
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


def main(kvmhostname: str):
    # XXX: support multiple KVM servers?
    # - zu Beginn: hostname des toten hosts angeben
    # - host via directory API out of service setzen
    # FIXME: difference in behaviour: "Evacuate VMs" button in adminui also sets node out of service, but
    # ring0 API `evacuate_vms` doesn't (probably because the kvm host usually calls this when already in maintenance)
    # Setting a node permanently out of service is not possible via directory API for now
    subprocess.run(["fc-directory", f"d.mark_node_service_status('{kvmhostname}', False, 60*60)"], check=True)  # fmt: skip
    # alternative: provide a clickable link in terminal and ask the user to set host out of service in browser.
    subprocess.run(["fc-directory", f"d.evacuate_vms('{kvmhostname}')"], check=True)  # fmt: skip
    # TODO: we might want to evacuate only after successful unlocking, to have the consul trigger closer to the actual unlocking

    rbd = Rbd()
    host_locked_images = collect_image_locks(kvmhostname, rbd)
    if not host_locked_images:
        print(
            f"Did not find any VM images locked by {kvmhostname}, nothing to rescue"
        )
        # XXX: host still out of service
        sys.exit(2)

    print(host_locked_images)

    # - zuerst oneshot fc-ipmitool `power status`: wenn host klar down ist, dann können alle rbd locks aufgeräumt werden
    # XXX: retries?
    fc_ipmi = Ipmitool(kvmhostname)
    power_status = fc_ipmi(
        "power", "status", capture_output=True
    ).stdout.strip()

    safe_to_unlock = False
    if power_status == "Chassis Power is off":
        # we can force-unlock all the collected images
        safe_to_unlock = True
    else:
        rich.print(
            f"{kvmhostname} status is'{power_status}', please ensure it is not running any VMs before continuing."
        )
        rich.print("Opening a SOL console for your interactive investigations:")
        # XXX: provide option for `ipmitool shell`, e.g. if wanting to force-unlock
        with open("/dev/tty", "r+b", buffering=0) as tty:
            _ = subprocess.run(
                [
                    "fc-ipmitool",
                    "-U",
                    fc_ipmi.ipmiuser,
                    kvmhostname,
                    "sol",
                    "activate",
                ],
                stdin=tty,
                stdout=tty,
                stderr=tty,
                env=fc_ipmi.env,
            )

    # - falls nicht:
    # XXX: - BMC nicht erreichbar: TBD
    # in practice, BMC connections can turn out to be rather flaky.
    # - interaktives Anzeigen der SOL

    if not safe_to_unlock:
        _ = input(
            f"About to force-unlock all VMs of {kvmhostname}, ensure host is down! [Enter to confirm]"
        )

    for img in host_locked_images:
        # XXX: error handling: locks can be gone, images might have changed
        lockinfo = rbd.rbd_("lock", "ls", img)[0]
        _ = rbd.rbd_(
            "lock",
            "remove",
            img,
            lockinfo["id"],
            lockinfo["locker"],
            use_json=False,
        )

    # XXX: Is there a way we can speed up/ trigger the ensures at the individual hosts?


if __name__ == "__main__":
    main(sys.argv[1])
