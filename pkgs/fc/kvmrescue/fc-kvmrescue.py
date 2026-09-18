#!/usr/bin/env nix-shell
#! nix-shell -p uv -i "uv run --script"
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["rich", "pydantic"]
# ///

import argparse
import ctypes
import getpass
import os
import subprocess
import sys
from collections.abc import Callable
from contextlib import nullcontext
from functools import cached_property, wraps
from ipaddress import IPv6Address
from socket import gethostname
from textwrap import dedent
from time import sleep
from typing import ClassVar, cast, overload

from pydantic import IPvAnyAddress, TypeAdapter
from rich import box, print
from rich.markup import escape
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    TextColumn,
    TimeElapsedColumn,
)
from rich.prompt import Confirm, Prompt
from rich.table import Table

from state import (
    BlocklistEntry,
    RbdImageSpec,
    RbdLock,
    RescueState,
    foreign_locks,
    locks_held_by,
)
from steps import (
    STEPS,
    STEPS_BY_NAME,
    RescueDone,
    StepDef,
    missing_prerequisites,
    run,
    step,
)

# we *could* extract them somewhere from the platform, but let's not do this for now.
RBD_POOLS = ["rbd.hdd", "rbd.ssd"]

# Lifetime of the host-global `ceph osd blocklist` entries we add in
# @blocklist_lockers. Plenty of time to handle a broken host, but short enough
# to recover on its own should we miss cleaning them up.
BLOCKLIST_TTL = 24 * 60 * 60


@overload
def plain(value: str) -> str: ...
@overload
def plain[T](value: T) -> T: ...
def plain(value: object) -> object:
    """Keep rich from swallowing `[...]` in data as console markup.

    Bracketed data is common here: IPv6 EntityAddrs (`[dead::1]:0/0`) and the
    repr'd argv in subprocess error messages. Only strings are affected, other
    objects go through rich's pretty printer untouched.
    """
    return escape(value) if isinstance(value, str) else value


def rich_link(url: str) -> str:
    return f"[link={url}]{url}[/link]"


def print_directory_link(hostname: str) -> None:
    url = f"https://directory.fcio.net/machine/list?search=name-{hostname}"
    # As an explicit OSC 8 hyperlink, so the terminal does not have to guess
    # where the URL ends.
    # On its own line for terminals that lack OSC 8 and do guess.
    print(f"   {rich_link(url)}")


def rich_sep(char: str = "=") -> None:
    print("[purple]" + f"{char}" * 80 + "[/purple]")


class Ipmitool:
    """Wrapper for calling the fc-ipmitool command, implementing the following
    supoporting features:
    - user name / password caching
    - mlock to avoid swapping these credentials
    - I/O redirection: optionally redirect to a real tty, e.g. for SOL
    """

    # Implement mlock to avoid swapping as we store sensitive data (like IPMI credentials)
    # Constants defined by kernel, not dynamically accessible here:
    # https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/include/uapi/asm-generic/mman.h#n18

    MCL_CURRENT: ClassVar[int] = 1
    MCL_FUTURE: ClassVar[int] = 2

    hostname: str

    _ipmipw: str | None = None
    _ipmiuser: str | None

    libc: ClassVar[ctypes.CDLL] = ctypes.CDLL("libc.so.6", use_errno=True)

    def __init__(self, hostname: str, ipmiuser: str | None = None) -> None:
        self.hostname = hostname
        self._ipmiuser = ipmiuser

    @classmethod
    def mlockall(cls) -> None:
        result = cast(int, cls.libc.mlockall(cls.MCL_CURRENT | cls.MCL_FUTURE))
        if result != 0:
            raise Exception("cannot lock memory, errno=%s" % ctypes.get_errno())

    @property
    def ipmipw(self) -> str:
        while not self._ipmipw:
            # allows clearing a wrong password by resetting the cached value to None
            self._ipmipw = getpass.getpass("IPMI access password: ")
        return self._ipmipw

    @property
    def ipmiuser(self) -> str:
        while not self._ipmiuser:
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

    def check_is_power_off(self) -> bool:
        """May raise a CalledProcessError, leaving handling of that to
        consumers."""
        power_status = self(
            "power", "status", capture_output=True
        ).stdout.strip()

        if power_status == "Chassis Power is off":
            # we can force-unlock all the collected images
            print("Power is [green]off[/green].")
            return True
        else:
            print(
                f"Power status is [orange1]'{escape(power_status)}'[/orange1].",
            )
            return False


class PoolMissing(Exception):
    """This cluster has no such pool.

    Expected: RBD_POOLS lists what a cluster *may* have, and not every cluster
    has every pool.
    """


def handle_image_gone[**P, R](f: Callable[P, R]) -> Callable[P, R]:
    """Wrap around any `rbd` call and provide an actionable message for the case
    of a missing image. Apply this at places where we can expect images to be
    gone due to non-atomicites.
    """

    @wraps(f)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        try:
            return f(*args, **kwargs)
        except subprocess.CalledProcessError as e:
            # typeshed types `stderr` as Any because it depends on the flags
            # `run` was called with; ours captures it as text.
            if (
                "error opening image" in (errmsg := cast(str, e.stderr) or "")
                and "No such file or directory" in errmsg
            ):
                raise RuntimeError(
                    f"Did not find image: {e}\n"
                    + "Try re-running the `collect_locks` step and continue step-wise from there."
                ) from e
            else:
                raise

    return wrapper


class Rbd:
    ceph_client_name: str
    # for now assuming default ceph conf location, while fc.qemu handles this explicitly

    def __init__(self) -> None:
        self.ceph_client_name = f"client.{gethostname()}"

    def validate_json_cmd[V](self, tp: type[V], *args: str) -> V:
        # `tp` may be any type pydantic can validate: a BaseModel subclass just
        # as well as a plain container like `list[str]`.
        return TypeAdapter(tp).validate_json(self.rbd_(*args))

    def pool_ls(self, pool: str) -> set[RbdImageSpec]:
        try:
            imgnames = self.validate_json_cmd(list[str], "ls", pool)
        except subprocess.CalledProcessError as e:
            # `rbd ls` exits 2 both for a missing pool and for other failures,
            # so go by the message to avoid swallowing anything else.
            # typeshed types `stderr` as Any because it depends on the flags
            # `run` was called with; ours captures it as text.
            stderr = cast(str, e.stderr)
            if "error opening pool" in stderr:
                raise PoolMissing(pool) from e
            raise
        return {RbdImageSpec(pool, imgname) for imgname in imgnames}

    def lock_ls(self, imgspec: RbdImageSpec) -> list[RbdLock]:
        return self.validate_json_cmd(list[RbdLock], "lock", "ls", str(imgspec))

    def rbd_(
        self,
        *args: str,
        use_json: bool = True,
        verbose: bool = False,
    ) -> str:
        """Run an `rbd` subcommand and hand back its raw output.

        Callers that want structured data go through `validate_json_cmd`, which
        lets pydantic parse the JSON straight into the target type.
        """
        format_arg = ["--format", "json"] if use_json else []
        cmd = ["rbd", "--name", self.ceph_client_name, *format_arg, *args]
        if verbose:
            print(cmd)
        result = subprocess.run(
            cmd, check=True, capture_output=True, text=True
        ).stdout
        if verbose:
            print(plain(result))
        return result


def item_progress() -> Progress:
    """Progress bar that names the item currently being worked on.

    The steps below walk one Ceph call per image or address, which is slow
    enough on a full pool that an operator wants to see it move -- and see what
    it is stuck on if it stops moving.
    """
    return Progress(
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        TextColumn("[dim]{task.fields[item]}"),
    )


def fmt_blocklist_address(address: IPvAnyAddress) -> str:
    if isinstance(address, IPv6Address):
        addresspart = f"[{address}]"
    else:
        addresspart = str(address)
    # `<IPAddr>:0/0` is a special EntityAddr that covers all ports and nonces as well
    return f"{addresspart}:0/0"


class KVMHostRescue:
    state: RescueState

    def __init__(self, yt_ticket: str | None) -> None:
        while not yt_ticket:
            if not Confirm.ask(
                "Did you already create a ticket for this rescue?", default=True
            ):
                print("Create a new ticket from")
                print(
                    "   "
                    + rich_link(
                        "https://wiki.flyingcircus.io/Qemu/KVM_operations_manual#semi-automated_KVM_host_evacuation"
                    )
                )
            yt_ticket = Prompt.ask("Enter ticket number")
        state = RescueState.load(yt_ticket=yt_ticket)
        pre_existing = bool(state)
        if not state:
            kvmhostname = Prompt.ask(
                "Enter hostname of the KVM host to evacute"
            )
            state = RescueState.new_state(kvmhostname, yt_ticket)
            state.save()
            print(f"Created new state file at [i]{state.path}[i]")
        else:
            print()
            print(
                f"This rescue operation is for host [b]{state.kvmhostname}[/b]."
            )

        recreate = False
        if pre_existing:
            print(
                f"Found existing rescue-state from {state.creation_date:%Y-%m-%d %H:%M %Z} at [i]{state.path}[i]."
            )
            _ = list_steps(yt_ticket)
            recreate = not Confirm.ask("Continue using that data?")
        if recreate:
            state.move_aside()
            state = RescueState.new_state(state.kvmhostname, yt_ticket)
        self.state = state

    @property
    def kvmhostname(self) -> str:
        return self.state.kvmhostname

    # lazy singletons
    @cached_property
    def rbd(self) -> Rbd:
        return Rbd()

    @cached_property
    def ipmi(self) -> Ipmitool:
        return Ipmitool(self.kvmhostname, ipmiuser=self.state.ipmi_user)

    # -- steps, in the order they run --------------------------------------

    @step()
    def add_ticket_text(self) -> None:
        """Add the rescue steps checklist to ticket."""

        print(
            f"Please extend the rescue ticket [b][link=https://yt.flyingcircus.io/issue/{self.state.yt_ticket}]{self.state.yt_ticket}[/link][/b] with the following:"
        )
        print()

        rich_sep()
        print(plain(self.ticket_template))
        rich_sep()

        while not Confirm.ask(
            "Have you copied the checklist to the rescue ticket?"
        ):
            pass

    @step()
    def set_out_of_service(self) -> None:
        """Have the operator take the host out of service in the directory."""
        # Setting a node permanently out of service is not possible via
        # directory API for now
        print(" > Set the host out of service in the directory:")
        print_directory_link(self.kvmhostname)
        print()
        while not Confirm.ask(
            f"Is host {self.kvmhostname} set out-of-service?"
        ):
            pass

    @step(skip=False)
    def ensure_host_offline(self) -> None:
        """Establish that the host is really down before touching its locks."""

        if "cleanup_start" in self.state.completed:
            print("Main rescue is finished, continuing…")
            return

        print(
            f"Power status of {self.kvmhostname} should be [i]off[/i]. Checking…"
        )
        try:
            if self.ipmi.check_is_power_off():
                print("Host is [green]safe to evacuate[/green].")
                return
        except subprocess.CalledProcessError as e:
            print(f"Error calling ipmitool: {escape(str(e))}")
        print(
            "Ensure the host is really down. You can now interact with the host if necessary."
        )
        while True:
            try:
                match Prompt.ask(
                    "Actions: Trigger a IPMI [b]power off[/b], connect to [b]SOL[/b] console, open an ipmitool [b]shell[/b], or [b]continue[/b] anyway?",
                    choices=["power off", "SOL", "shell", "continue"],
                ):
                    # In practice, BMC connections can turn out to be rather flaky.
                    # But retrying or deactivating-activating the SOL is left as a
                    # task to the operator.
                    case "power off":
                        print("[i]ipmitool power off")
                        _ = self.ipmi("power", "off")
                        sleep(5)
                        if self.ipmi.check_is_power_off():
                            return
                        else:
                            continue
                    case "SOL":
                        print(
                            "Opening a SOL console for your interactive investigations:"
                        )
                        _ = self.ipmi("sol", "activate", tty=True)
                    case "shell":
                        print("Opening an [i]ipmitool shell[/i]")
                        _ = self.ipmi("shell", tty=True)
                    case "continue":
                        print(
                            f"[yellow]{self.kvmhostname} must not be reachable, otherwise its Consul will prevent machines from starting on other hosts. If the host cannot be set down reliably, consider manually disconneting its network."
                        )
                    case _:
                        print("[orange1]Invalid choice.")
                        continue
            except subprocess.CalledProcessError as e:
                print(escape(str(e)))
            if Confirm.ask("Continue the evacuation?"):
                break

    @step()
    def collect_locks(self) -> None:
        """Find the VM images the dead host still holds Ceph locks on."""
        locked_images: dict[RbdImageSpec, list[RbdLock]] = {}
        # Listed up front so the bar below has a total: one `rbd ls` per pool is
        # cheap next to the `lock ls` per image that follows.
        imgspecs: list[RbdImageSpec] = []
        for pool in RBD_POOLS:
            try:
                imgspecs.extend(self.rbd.pool_ls(pool))
            except PoolMissing:
                # not adding a state warning: some clusters normally do not have all pools
                print(
                    f"[dim]No pool {pool} in this cluster, skipping it.[/dim]"
                )

        with item_progress() as progress:
            task = progress.add_task(
                "Checking locks", total=len(imgspecs), item=""
            )
            for imgspec in imgspecs:
                progress.update(task, item=str(imgspec))
                lockers = handle_image_gone(self.rbd.lock_ls)(imgspec)
                progress.advance(task)
                if not any(lock.id == self.kvmhostname for lock in lockers):
                    continue
                if len(lockers) > 1:
                    held_by = ", ".join(sorted(lock.id for lock in lockers))
                    self.state.warn(
                        f"{imgspec} is locked by {held_by}, but locking is expected to be exclusive."
                    )
                # Foreign locks are kept alongside ours, so break_locks can tell
                # them apart and the state file shows the operator what was
                # actually there.
                locked_images[imgspec] = lockers

        self.state.locked_images = locked_images
        self.state.save()

        if not locked_images:
            raise RescueDone(
                f"Did not find any VM images locked by {self.kvmhostname}, nothing to rescue."
            )
        else:
            print(f"Found {len(locked_images)} locked VM images.")

    @step()
    def blocklist_lockers(self) -> None:
        """Blocklist the dead host's Ceph client addresses ahead of time."""
        # By default, breaking a lock causes the address of the broken client
        # to be osd-blocklisted. We do want that, but with a larger blocklist
        # entry TTL, and for the full host. So adding that entry explicitly
        # ahead of time.
        ceph_auth_id = gethostname()
        locker_addresses = self.state.locker_addresses
        with item_progress() as progress:
            task = progress.add_task(
                "Blocklisting", total=len(locker_addresses), item=""
            )
            for locker_address in locker_addresses:
                address = fmt_blocklist_address(locker_address)
                progress.update(task, item=address)
                _ = subprocess.run(
                   [
                    "ceph", "--id", ceph_auth_id,
                    "osd", "blocklist", "add",
                    address, f"{BLOCKLIST_TTL}",
                   ],
                   check=True,
                   capture_output=True,
                   text=True,
               )  # fmt: skip

                # continually persist the blocklist state, such that already blocked
                # hosts do not get lost when a single loop iteration fails.
                self.state.blocklist_entries.add(
                    BlocklistEntry(
                        address=address,
                    )
                )
                self.state.save()
                progress.advance(task)

    @step()
    def break_locks(self) -> None:
        """Remove the dead host's locks from the collected images."""
        with item_progress() as progress:
            task = progress.add_task(
                "Breaking locks", total=len(self.state.locked_images), item=""
            )
            for imgspec, locks in self.state.locked_images.items():
                progress.update(task, item=str(imgspec))
                for foreign in foreign_locks(locks, self.kvmhostname):
                    self.state.warn(
                        f"{imgspec} is also locked by {foreign.id}; left that lock alone, please check afterwards."
                    )
                for lockinfo in locks_held_by(locks, self.kvmhostname):
                    _ = handle_image_gone(self.rbd.rbd_)(
                        "lock",
                        "remove",
                        # speeds up the process and is okay due to us having created a blocklist entry earlier
                        "--rbd_blocklist_on_break_lock=false",
                        str(imgspec),
                        lockinfo.id,
                        lockinfo.locker,
                        use_json=False,
                    )
                progress.advance(task)

    @step()
    def evacuate_vms(self) -> None:
        """Call directory to move VMs to remaining hosts."""
        # - finally evacuate all VMs away
        _ = subprocess.run(["fc-directory", f"d.evacuate_vms('{self.kvmhostname}')"], check=True)  # fmt: skip

    @step()
    def cleanup_start(self) -> None:
        """Evacuation is done, start cleanup."""

        print(
            "Host evacuation is done. The remaining steps are cleanup.",
            "To handle the immediate emergency, feel free to interrupt and continue later.",
            sep="\n",
        )

        if not Confirm.ask("Continue with cleanup?"):
            raise KeyboardInterrupt()

    @step()
    def investigate_warnings(self) -> None:
        """Acknowledge the warnings discovered during the rescue process."""
        if not self.state.warnings:
            return
        report_warnings(self.state)

        print()
        while not Confirm.ask("Did you investigate all warnings above?"):
            self.state.warnings = set()

    @step(skip=False)
    def cleanup_check_machine_is_clean(self) -> None:
        """Verify the machine is clean before removing its blocklist entries."""

        while True:
            if Confirm.ask("Start the host and set it back in service?"):
                print("Starting the host via IPMI.")
                _ = self.ipmi("power", "on")
                # XXX: we could print an SOL or wait for the host to ping successfully
                if Confirm.ask(f"Is {self.kvmhostname} clean and reachable?"):
                    print(
                        "Please ensure that the host is not running any VMs (`fc-qemu ls`)."
                    )
                    # XXX: We could additionally check for the servicing status via directory API
                    if Confirm.ask("Is the host running any VMs?"):
                        print(
                            "As the host has been successfully evacuated, we need to get rid of these stale processes."
                        )
                        print("Please reboot the host.")
                    else:
                        break
                else:
                    print(
                        "Host needs to either be properly down, or up and confirmed to hold no VMs."
                    )
            else:
                print(
                    "You can decide to leave the host down for now. It is still important that the host is properly down."
                )
                if Confirm.ask("Is host set properly down?"):
                    self.state.cleanup_stay_down = True
                    break

    @step()
    def blocklist_cleanup(self) -> None:
        """Remove ceph blocklist entries again."""
        try:
            with item_progress() as progress:
                task = progress.add_task(
                    "Removing block",
                    total=len(self.state.blocklist_entries),
                    item="",
                )
                for entry in self.state.blocklist_entries:
                    progress.update(task, item=" ".join(entry.cleanup_command))
                    _ = subprocess.run(
                        entry.cleanup_command,
                        check=True,
                        capture_output=True,
                        text=True,
                    )

                    progress.advance(task)

        except subprocess.CalledProcessError:
            print(
                "[red]Error:[/red] Error running the commands below.",
                "Try executing the following script manually on a [b]ceph mon[/b] host of this cluster:",
                sep="\n",
            )
            rich_sep()
            print(
                "\n".join(
                    plain(" ".join(entry.cleanup_command))
                    for entry in self.state.blocklist_entries
                )
            )
            rich_sep()
            print()

            if not Confirm.ask("Did the script succeed?"):
                raise

    @step()
    def mark_nonprod(self) -> None:
        """Mark host usage as non-production until observed to be stable again."""
        if self.state.cleanup_stay_down:
            raise RescueDone(
                "You earlier decided the host should stay down. We are done here."
            )
        print(
            f" > Set the [b]KVM production use[/b] of {self.kvmhostname} to [i]non-production[/i] (if cluster capacity allows) or [i]prefer non-production[/i]. "
        )
        print_directory_link(self.kvmhostname)
        while not Confirm.ask("Did you adjust the [b]KVM production use[/b]?"):
            pass

    @step()
    def set_back_in_service(self) -> None:
        """Set machine back in service."""
        print(" > Set machine back in service in directory:")
        print_directory_link(self.kvmhostname)
        while not Confirm.ask(
            "Did you set the machine back in service in the directory?"
        ):
            pass

    # --- end of steps ---

    @property
    def ticket_template(self) -> str:
        """Generate an instructional markdown representation of the current
        rescue state, to be used as CommonMark text for a YT Ticket"""
        ticket_segments = [f"## `fc-kvmrescue` run on `{gethostname()}`:", ""]
        ticket_segments.extend(
            [
                common_mark_checkboxline(
                    definition.name,
                    checked=definition.name in self.state.completed,
                )
                for definition in STEPS
            ]
        )
        ticket_segments.append("\n")

        if self.state.warnings:
            ticket_segments.extend(["### Warnings", ""])
            ticket_segments.append(
                "Things that looked off and should be investigated:"
            )
            ticket_segments.extend(
                [
                    common_mark_checkboxline(warning)
                    for warning in sorted(self.state.warnings)
                ]
            )
            ticket_segments.append("\n")

        return "\n".join(ticket_segments)


def common_mark_checkboxline(
    text: str, checked: bool = False, indent_level: int = 0
) -> str:
    """indent_level uses 2 spaces per level"""
    indent = "  " * indent_level
    # insert necessary indentation for multi-line text
    body = text.strip().replace("\n", "\n" + indent)
    return f"{indent}- [{'x' if checked else ' '}] {body}"


def report_warnings(state: RescueState) -> None:
    if not state.warnings:
        return
    print()
    print("[yellow]Things that looked off and should be investigated:")
    for warning in sorted(state.warnings):
        print(f"  - {plain(warning)}")


def list_steps(yt_ticket: str | None) -> int:
    state = RescueState.load(yt_ticket) if yt_ticket else None
    if state is None and yt_ticket:
        print("[orange1]Unable to load state file. Showing an empty run.")
        state = None
    completed = state.completed if state else []
    title = "Rescue steps"
    title += f" for {state.kvmhostname}" if state else ""

    table = Table(
        title=title,
        title_justify="left",
        box=box.SIMPLE,
    )
    table.add_column("#", justify="right", style="dim")
    # the first two columns get whatever they need, the docs absorb the squeeze
    table.add_column("step", no_wrap=True)
    table.add_column("status", no_wrap=True)
    table.add_column("description")

    for definition in STEPS:
        if definition.name in completed:
            status = "[green]done[/green]"
        else:
            status = "[yellow]pending[/yellow]"
        if not definition.skip:
            # runs again on every pass, done or not
            status += " [dim](always runs)[/dim]"
        table.add_row(
            str(definition.index + 1),
            definition.name,
            status,
            definition.doc,
        )

    print(table)

    if state:
        report_warnings(state)
    return 0


class Args(argparse.Namespace):
    """The parsed command line.

    Declared so the attributes are typed: `Namespace` hands them back as `Any`.

    They are deliberately left without defaults -- argparse populates every one
    of them from the parser below, and a default repeated here would take effect
    whenever its flag is absent, silently overriding the action it belongs to if
    the two ever drifted apart. Hence the ignores: the checker cannot see that
    argparse does the initialising.
    """

    yt_ticket: str | None  # pyright: ignore[reportUninitializedInstanceVariable]
    step: str | None  # pyright: ignore[reportUninitializedInstanceVariable]
    list_steps: bool  # pyright: ignore[reportUninitializedInstanceVariable]
    skip: bool  # pyright: ignore[reportUninitializedInstanceVariable]


def parse_args(argv: list[str]) -> Args:
    parser = argparse.ArgumentParser(
        description="Rescue the VMs of a dead KVM host.",
        epilog="Without a step, the whole sequence runs; steps already recorded as done skip themselves, so this doubles as resuming an interrupted rescue.",
    )
    _ = parser.add_argument(
        "yt_ticket",
        nargs="?",
        help="ticket identifier of this particular rescue (asked for if omitted)",
    )
    _ = parser.add_argument(
        "--step",
        choices=[definition.name for definition in STEPS],
        help="run only this step",
    )
    _ = parser.add_argument(
        "--list",
        action="store_true",
        dest="list_steps",
        help="show the steps and what has already run, then exit",
    )
    _ = parser.add_argument(
        "--no-skip",
        action="store_false",
        dest="skip",
        help="run steps even if they are already recorded as done",
    )
    return parser.parse_args(argv, namespace=Args())


def main(argv: list[str]) -> int:
    args = parse_args(argv[1:])
    exitcode = 0

    if args.list_steps:
        return list_steps(args.yt_ticket)

    rescue = KVMHostRescue(args.yt_ticket)
    print(
        "Progress is saved per step, re-run to continue. [b]^C[/b] to interrupt."
    )

    start: StepDef | None = None
    skip = args.skip
    if args.step:
        # run only this single step. We assume this is done deliberately, so no
        # skipping
        start = STEPS_BY_NAME[args.step]
        skip = False
        missing = missing_prerequisites(start, rescue.state.completed)
        if missing:
            print(
                f"[red]{start.name} requires steps that have not run yet:[/red]"
            )
            for position, definition in enumerate(missing, start=1):
                print(f"  {position}. {definition.name}")
            print(
                f"Run `{argv[0]} {rescue.state.yt_ticket}` to work through the sequence from where it stopped."
            )
            return 1

    try:
        for rstep in (stepgen := run(rescue, start, skip=skip)):
            if rstep.skipped:
                print(f"[dim]skip {rstep.definition.name} (already done)[/dim]")
            else:
                print()
                headline = f"[b]{rstep.definition.name}[/b]"
                if rstep.definition.doc:
                    headline += f": {rstep.definition.doc}"
                print(headline)
            rstep()
            if args.step:
                print(f"Finished step [b]{rstep.definition.name}[/b].")
                if next_step := next(stepgen, None):
                    print(
                        f"Next step to invoke manually would be [b]{next_step.definition.name}[/b]"
                    )
                break
            print()
            rich_sep("-")
            print()
    except KeyboardInterrupt:
        print(
            f"Interrupted. Run `{argv[0]} {rescue.state.yt_ticket}` to continue."
        )
        raise
    except RescueDone as done:
        print(f"[green]{plain(str(done))}[/green]")
        if "set_out_of_service" in rescue.state.completed:
            # Ending early leaves that first step's effect in place, and nothing
            # later undoes it.
            print(
                f"[yellow]Note: {rescue.kvmhostname} is still set out-of-service."
            )
        exitcode = 2
    finally:
        report_warnings(rescue.state)
        print("\n")

        print(
            f"Update the rescue ticket [b][link=https://yt.flyingcircus.io/issue/{rescue.state.yt_ticket}]{rescue.state.yt_ticket}[/link][/b] as follows:"
        )
        rich_sep()
        print(plain(rescue.ticket_template))
        rich_sep()
    return exitcode


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        sys.exit(110)
