#!/usr/bin/env nix-shell
#! nix-shell -p uv -i "uv run --script"
#
# /// script
# requires-python = ">=3.12"
# dependencies = ["rich", "pydantic"]
# ///
#
# ⬆ keep in sync with pyproject.toml, to allow copying this as a standalone
# quick-edit script for quick changes.

import argparse
import getpass
import os
import re
import shlex
import subprocess
import sys
from collections.abc import Callable
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from socket import gethostname
from textwrap import dedent
from time import monotonic, sleep
from typing import Self, overload

from pydantic import BaseModel, TypeAdapter
from rich import box
from rich.columns import Columns
from rich.console import Console, Group
from rich.live import Live
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)
from rich.prompt import Confirm, Prompt
from rich.table import Table
from rich.text import Text

STATE_DIR = Path("/var/lib/fc-kvmrescue")

# Set once from `--dry-run`. Every callout that would change the cluster, the
# host or the state file checks it -- `grep DRY_RUN` lists them all.
DRY_RUN = False

# Lifetime of the host-global `ceph osd blocklist` entries added in
# blocklist_lockers. Plenty of time to handle a broken host, but short enough to
# recover on its own should we miss cleaning them up.
BLOCKLIST_TTL = 24 * 60 * 60

MANUAL_URL = "https://wiki.flyingcircus.io/Qemu/KVM_operations_manual#semi-automated_KVM_host_evacuation"

# How monitor_affected_vms watches the VMs come back.
PING_TIMEOUT = 2  # seconds a VM gets to answer a single ping
POLL_INTERVAL = 10  # seconds before a VM's state counts as outdated
TICK_INTERVAL = 0.2  # seconds between servicing the queue and redrawing
# A host can hold 200 VMs, and each one costs an `rbd lock ls` plus a ping.
# Checked one after the other a single pass would take minutes.
CHECK_WORKERS = 32

# The rescue runs the steps in this order, and ALWAYS_RUN holds the subset that
# runs again on every pass even once recorded as done. Both are filled by @step
# in definition order, see the Rescue class below.
STEPS: list[str] = []
ALWAYS_RUN: set[str] = set()


# --- talking to the operator ------------------------------------------------

console = Console(highlight=False)


def say(message: str = "", style: str = "") -> None:
    """Print a line, taking any `[...]` in it literally.

    Nearly everything here interpolates data, and rich reads `[` followed by a
    letter as console markup and drops it: `[fe80::1]:0/0` would print as
    `:0/0`, a `- [x]` checklist line as `- `. Colour goes through `style`, so no
    call site has to remember to escape anything.

    The `Prompt`/`Confirm` questions below are the exception that proves it:
    those are fixed strings with no data in them, so they may use markup.
    """
    console.print(message, style=style, markup=False)


def show_link(url: str):
    "A stand-out link"
    console.print()
    console.print(f" 🔗 {url}")
    console.print()


def show_command(cmd: list[str]) -> None:
    """Report a callout a dry run is making instead of it."""
    say(f"\n $ {shlex.join(cmd)}", style="dim")


def separator(char: str = "=") -> None:
    say(char * 80, style="dim")


# The three helpers below own the blank lines around what they print, so no
# caller has to space its output by hand.


def heading(text: str, style: str = "") -> None:
    """Open a new block of output."""
    say()
    say(text, style=style)


def framed(text: str) -> None:
    """Print a block that is meant to be copied out, between separators."""
    separator()
    say(text)
    separator()


def divider() -> None:
    """Close off a finished step."""
    say()
    separator("-")
    say()


def confirm(question: str, default: bool | None = None) -> bool:
    """Ask a yes/no question, set off from the output above it.

    Without a `default` there is no answer but an explicit yes or no, which is
    what anything that discards state or moves the rescue on wants.
    """
    say()
    if default is None:
        return Confirm.ask(question)
    return Confirm.ask(question, default=default)


def acknowledge(question: str) -> None:
    """Ask until the operator confirms. Nothing but "yes" gets past this."""
    while not confirm(question):
        pass


def operator_task(instruction: str, question: str, url: str = "") -> None:
    """Hand a task to the operator to do by hand, then wait for them."""
    say(f" 👩‍💻 {instruction}")
    if url:
        console.print()
        console.print(f"   {url}")
    acknowledge(" " + question)


def directory_url(hostname: str) -> str:
    return f"https://directory.fcio.net/machine/list?search=name-{hostname}"


def ticket_url(yt_ticket: str) -> str:
    return f"https://yt.flyingcircus.io/issue/{yt_ticket}"


def progress_bar() -> Progress:
    """Progress bar that names the item currently being worked on.

    The steps below make one Ceph call per image or address, which is slow
    enough on a full pool that an opserator wants to see it move -- and see what
    it is stuck on if it stops moving.
    """
    return Progress(
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        MofNCompleteColumn(),
        TimeElapsedColumn(),
        TimeRemainingColumn(),
        # markup off: the item is an image spec or a Ceph address.
        TextColumn("{task.fields[item]}", style="dim", markup=False),
    )


# --- persisted state --------------------------------------------------------


class RbdLock(BaseModel):
    """One entry of `rbd lock ls`."""

    id: str  # the name the locking host registered, i.e. its hostname
    locker: str  # the Ceph client holding it, e.g. `client.14612`
    address: str  # Ceph EntityAddr, e.g. `172.20.4.101:0/3733721661`


class RescueState(BaseModel):
    """Everything the steps gather, written out after each one so an
    interrupted rescue can be resumed."""

    # The host identifies the rescue: one state file per host, so a second run
    # for the same host resumes it instead of opening a rival rescue.
    kvmhostname: str
    yt_ticket: str = ""  # filled in by the register_ticket step
    created: datetime
    ipmi_user: str = ""
    completed: list[str] = []
    # The locks on every `pool/image` the dead host holds a lock on. Foreign
    # locks are kept alongside ours, so break_locks can tell them apart and the
    # state file shows the operator what was actually there.
    locked_images: dict[str, list[RbdLock]] = {}
    # The `ceph osd blocklist` entries we added, in `<addr>:0/0` form.
    blocklist: list[str] = []
    # Anything that looked off while stepping through, presented to the operator
    # as a checklist at the end instead of making them scroll back.
    warnings: list[str] = []

    @classmethod
    def load(cls, kvmhostname: str) -> "RescueState | None":
        """Read the state file without prompting, if there is one."""
        try:
            return cls.model_validate_json(state_path(kvmhostname).read_text())
        except FileNotFoundError:
            return None

    @property
    def path(self) -> Path:
        return state_path(self.kvmhostname)

    def save(self) -> None:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.path.write_text(self.model_dump_json(indent=2))

    def mark_done(self, stepname: str) -> None:
        if stepname not in self.completed:
            self.completed.append(stepname)
        self.save()

    def warn(self, message: str) -> None:
        if message not in self.warnings:
            self.warnings.append(message)
        self.save()

    @property
    def locker_addresses(self) -> list[str]:
        """Blocklist entries for the addresses the dead host locks from.

        Never a foreign locker's: we only ever break our dead host's locks.
        """
        return sorted(
            {
                blocklist_address(lock.address)
                for locks in self.locked_images.values()
                for lock in locks
                if lock.id == self.kvmhostname
            }
        )


def state_path(kvmhostname: str) -> Path:
    return STATE_DIR / f"{kvmhostname}.json"


# Ceph EntityAddrs look like `172.20.4.101:0/3733721661` or `[dead::1]:0/0`,
# optionally prefixed with the messenger protocol version (`v1:`/`v2:`).
ENTITY_ADDR = re.compile(
    r"^(?:v[12]:)?(?P<addr>\[[0-9a-fA-F:.]+\]|[0-9.]+):\d+/\d+$"
)


def blocklist_address(entity_addr: str) -> str:
    """Turn a locker's EntityAddr into a blocklist entry for the whole client.

    `<addr>:0/0` is the special form covering all ports and nonces, so one entry
    per address is enough. The address part is taken verbatim, to avoid a
    mismatch from re-formatting an IPv6 address.
    """
    match = ENTITY_ADDR.match(entity_addr)
    if not match:
        raise ValueError(f"not a Ceph EntityAddr: {entity_addr!r}")
    return f"{match['addr']}:0/0"


def vm_name(image: str) -> str:
    """The VM an image belongs to: `rbd.hdd/test00.root` -> `test00`.

    fc.qemu gives a VM one volume per purpose (`.root`, `.swap`, `.tmp`), so
    several images fold back onto the same VM. Only the last suffix is dropped,
    leaving a dotted VM name intact.
    """
    _, _, volume = image.partition("/")
    return volume.rsplit(".", 1)[0]


@dataclass
class VmStatus:
    """What the last completed check found out about one VM."""

    name: str
    locker: str = ""  # host holding its root lock, empty when nobody does
    new_locker: bool = False
    pings: bool = False
    checked_at: float = 0.0  # monotonic clock, 0 while never checked
    checking: bool = False  # a check for it is running right now

    def outdated(self, now: float) -> bool:
        return not self.checking and now - self.checked_at >= POLL_INTERVAL

    @property
    def healthy(self):
        return self.pings and self.new_locker


def check_vm(name: str, root_image: str, dead_host: str) -> VmStatus:
    """Poll one VM: who holds its root lock, and does it answer a ping.

    Healthy means another host has taken the root lock and the VM is back on
    the network. A lock still held by the dead host means it has not moved.
    """
    locker = ""
    try:
        locks = list_locks(root_image)
        locker = locks[0].id if locks else ""
    except (subprocess.CalledProcessError, RuntimeError):
        # Image gone or the cluster busy -- treat as unlocked and retry
        # next round rather than tearing down the whole watch.
        locker = ""
    pings = (
        subprocess.run(  # noqa: PLW1510
            ["ping", "-n", "-c", "1", "-W", str(PING_TIMEOUT), name],
            capture_output=True,
        ).returncode
        == 0
    )
    return VmStatus(name, locker, locker not in ("", dead_host), pings)


VM_LEGEND = "⟳ checking · P pingable · L lock status · name@host = lock holder"


class VmMonitor:
    """Keeps the check workers busy and the VM states fresh.

    `tick()` reaps whatever finished and refills the pool; it never blocks, so
    the caller is free to redraw between ticks. That is the difference from
    checking every VM in lockstep: a slow `rbd lock ls` on one VM no longer
    holds up the results for all the others.

    Only `tick()` touches `statuses`, and it runs in the caller's thread, so
    the workers share nothing and no locking is needed.
    """

    def __init__(
        self, names: list[str], roots: dict[str, str], dead_host: str
    ) -> None:
        self.statuses = {name: VmStatus(name) for name in names}
        self.roots = roots
        self.dead_host = dead_host
        self.pool = ThreadPoolExecutor(max_workers=CHECK_WORKERS)
        self.running: dict[Future[VmStatus], str] = {}

    @property
    def all_healthy(self) -> bool:
        """Every VM has been seen back. The loop waits on nothing else."""
        return all(status.healthy for status in self.statuses.values())

    @property
    def healthy_count(self) -> int:
        return sum(status.healthy for status in self.statuses.values())

    @property
    def checking(self) -> list[str]:
        return sorted(self.running.values())

    def tick(self) -> None:
        """Collect finished checks and start as many new ones as will fit."""
        for future in [f for f in self.running if f.done()]:
            name = self.running.pop(future)
            try:
                self.statuses[name] = future.result()
            except Exception as error:  # noqa: BLE001
                # One unhappy VM must not end a watch over 200 of them; hold
                # the old state and let the next round try again.
                say(f"Checking {name} failed: {error}", style="orange1")
                self.statuses[name].checked_at = monotonic()
                self.statuses[name].checking = False

        now = monotonic()
        # Oldest information first, so nothing starves while the pool is busy.
        outdated = sorted(
            (s for s in self.statuses.values() if s.outdated(now)),
            key=lambda status: status.checked_at,
        )
        for status in outdated[: CHECK_WORKERS - len(self.running)]:
            status.checking = True
            self.running[self.pool.submit(self.check, status.name)] = (
                status.name
            )

    def check(self, name: str) -> VmStatus:
        """Runs in a worker thread, and touches nothing the others touch."""
        status = check_vm(name, self.roots[name], self.dead_host)
        status.checked_at = monotonic()
        return status

    def __enter__(self) -> Self:
        return self

    def __exit__(self, *exception: object) -> None:
        self.pool.shutdown(wait=False, cancel_futures=True)


def vm_cell(status: VmStatus) -> Text:
    """One VM in as few characters as 200 of them allow.

    `⟳` marks a check that is running right now. The colour keeps reporting
    what the last completed check found, so a VM in flight still shows whether
    it was last seen back or missing.
    """

    def styled(text: str, status: bool, checking: bool, style: str = "") -> str:
        if checking:
            style = "deep_sky_blue1 blink2"
        elif style:
            # Allow manual style override but indicate WIP
            pass
        elif status:
            style = "green"
        else:
            style = "yellow"
        return f"[{style}]{text}[/{style}]"

    text = ""
    text += styled("L", status.new_locker, status.checking)
    text += styled("P", status.pings, status.checking)
    text += " "
    url = directory_url(status.name)
    text += styled(
        f"[link={url}]{status.name}[/link]", status.healthy, status.checking
    )
    if status.locker:
        text += styled(f"@{status.locker}", False, status.checking, "grey50")
    return Text.from_markup(text)


def vm_overview(statuses: list[VmStatus]) -> Columns:
    """Every VM as a compact cell, the ones still pending first.

    Trimmed to what fits on the screen. Pending VMs sort first, so a long list
    loses healthy ones off the end -- the ones nobody needs to look at.
    """
    ordered = sorted(statuses, key=lambda status: (status.healthy, status.name))
    cells = [vm_cell(status) for status in ordered]
    width = max((len(cell.plain) for cell in cells), default=1) + 2
    fits = max(1, console.width // width) * max(1, console.height - 8)
    if len(cells) > fits:
        hidden = len(cells) - fits + 1
        cells = cells[: fits - 1]
        cells.append(Text(f"… {hidden} more", style="dim"))
    return Columns(cells, equal=True, padding=(0, 1))


# --- talking to ceph and the BMC --------------------------------------------


def rbd(*args: str, changes: bool = False) -> str:
    """Run an `rbd` subcommand as this host's client and return its output.

    `changes` marks a subcommand that modifies the cluster, so a dry run shows
    it rather than running it.
    """
    cmd = ["rbd", "--name", f"client.{gethostname()}", *args]
    if changes and DRY_RUN:
        show_command(cmd)
        return ""
    try:
        return subprocess.run(
            cmd, check=True, capture_output=True, text=True
        ).stdout
    except subprocess.CalledProcessError as e:
        # Images can disappear between collecting and breaking their locks.
        if (
            "error opening image" in e.stderr
            and "No such file or directory" in e.stderr
        ):
            raise RuntimeError(
                f"Did not find image: {e}\n"
                "Re-run the `collect_locks` step and continue step-wise from there."
            ) from e
        raise


def list_images(pool: str) -> list[str]:
    """The `pool/image` specs of every image in the pool."""
    names = TypeAdapter(list[str]).validate_json(
        rbd("ls", "--format", "json", pool)
    )
    return [f"{pool}/{name}" for name in names]


def list_locks(image: str) -> list[RbdLock]:
    return TypeAdapter(list[RbdLock]).validate_json(
        rbd("lock", "ls", "--format", "json", image)
    )


def ceph(*args: str, changes: bool = False) -> str:
    """Run a `ceph` command as this host's client and return its output.

    `changes` marks a command that modifies the cluster, so a dry run shows it
    rather than running it.
    """
    cmd = ["ceph", "--id", gethostname(), *args]
    if changes and DRY_RUN:
        show_command(cmd)
        return ""
    return subprocess.run(
        cmd,
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def rbd_pools() -> list[str]:
    """The pools of this cluster that have the `rbd` application enabled.

    Asked of the cluster rather than hard-coded, so a cluster that does not have
    every pool -- or gains one -- needs no change here.
    """
    # Without a pool name, `application get` dumps them all:
    # {"rbd.hdd": {"rbd": {}}, "cephfs_data": {"cephfs": {...}}}
    applications = TypeAdapter(dict[str, dict[str, object]]).validate_json(
        ceph("osd", "pool", "application", "get", "--format", "json")
    )
    return sorted(name for name, apps in applications.items() if "rbd" in apps)


def blocklist_rm_command(address: str) -> list[str]:
    """How to drop a blocklist entry again.

    A command rather than a call, because blocklist_cleanup also prints it for
    the operator to run by hand should we fail to.

    """
    return ["ceph", "osd", "blocklist", "rm", address]


class Ipmi:
    """Runs `fc-ipmitool` against the host being rescued.

    The password is asked for once and then kept for the rest of the run. It is
    handed over through the environment (which is what fc-ipmitool's `-E`
    reads) rather than through argv, so it does not show up in `ps`.
    """

    def __init__(self, hostname: str, user: str) -> None:
        self.hostname = hostname
        self.user = user
        self.password = ""

    def _command(self, args: tuple[str, ...]) -> list[str]:
        return ["fc-ipmitool", "-U", self.user, self.hostname, *args]

    def _env(self) -> dict[str, str]:
        while not self.password:
            self.password = getpass.getpass("IPMI access password: ")
        # A copy per call, so the password neither leaks into unrelated
        # subprocesses nor outlives this invocation.
        return {**os.environ, "IPMI_PASSWORD": self.password}

    def run(self, *args: str) -> str:
        """Run a command and return its output."""
        return subprocess.run(
            self._command(args),
            check=True,
            env=self._env(),
            capture_output=True,
            text=True,
            errors="replace",
        ).stdout

    def interactive(self, *args: str) -> None:
        """Run a command on the real terminal, for SOL and the ipmitool shell."""
        show_command(self._command(args))
        with open("/dev/tty", "r+b", buffering=0) as terminal:
            subprocess.run(
                self._command(args),
                check=True,
                env=self._env(),
                stdin=terminal,
                stdout=terminal,
                stderr=terminal,
            )

    def change(self, *args: str) -> None:
        """Run a command that changes the host, and show what it said.

        Only power control goes through here. `sol`/`shell` stay live in a dry
        run: they hand the operator a console but change nothing themselves.
        """
        show_command(self._command(args))
        if DRY_RUN:
            return
        say(self.run(*args).strip())
        sleep(5)

    def is_powered_off(self) -> bool:
        """Raises CalledProcessError when the BMC cannot be reached."""
        try:
            status = self.run("power", "status").strip()
        except subprocess.CalledProcessError as e:
            say(f"Error calling ipmitool: {e}", style="orange1")
            return False
        if status == "Chassis Power is off":
            say("Power is off.", style="green")
            return True
        say(f"Power status is '{status}'.", style="orange1")
        return False


# --- the rescue itself ------------------------------------------------------


StepMethod = Callable[["Rescue"], None]


# Spelled out as overloads, so a checker can tell the two call shapes apart.
@overload
def step(fn: StepMethod) -> StepMethod: ...
@overload
def step(*, always: bool) -> Callable[[StepMethod], StepMethod]: ...


def step(fn: StepMethod | None = None, *, always: bool = False):
    """Register a method as a rescue step. Definition order is run order.

    A step's prerequisites are simply every step defined above it, which is what
    lets an interrupted rescue resume and `--list` tell the truth without
    running anything.

    `@step(always=True)` marks a step that runs again on every pass even once
    recorded as done: a safety gate that wants re-confirming.
    """

    # Positional-only (`/`), so it matches the plain `Callable` that the
    # second overload above promises to hand back.
    def register(method: StepMethod, /) -> StepMethod:
        STEPS.append(method.__name__)
        if always:
            ALWAYS_RUN.add(method.__name__)
        return method

    # Bare `@step` passes the method straight in; `@step(...)` passes nothing
    # and wants the registering decorator back.
    return register(fn) if fn else register


def step_doc(name: str) -> str:
    """First docstring line of a step, for `--list` and the run headline."""
    lines = (getattr(Rescue, name).__doc__ or "").strip().splitlines()
    return lines[0] if lines else ""


class Rescue:
    """The steps, in the order they run."""

    def __init__(self, state: RescueState) -> None:
        self.state = state
        self.hostname = state.kvmhostname
        self._ipmi: Ipmi | None = None

    @property
    def ipmi(self) -> Ipmi:
        """Set up on first use: most steps never talk to the BMC."""
        if self._ipmi is None:
            while not self.state.ipmi_user:
                self.state.ipmi_user = Prompt.ask(
                    f"IPMI user for {self.hostname}"
                )
            self.state.save()
            self._ipmi = Ipmi(self.hostname, self.state.ipmi_user)
        return self._ipmi

    @step
    def register_ticket(self) -> None:
        """Register rescue ticket"""
        if self.state.yt_ticket:
            say(f" Rescue ticket is {self.state.yt_ticket}.")
            return
        say(" 👩‍💻 You need to manually create a new ticket for this rescue: ")
        show_link(MANUAL_URL)
        while not self.state.yt_ticket:
            self.state.yt_ticket = Prompt.ask(" Ticket number")
        self.state.save()

    @step
    def add_ticket_text(self) -> None:
        """Ensure ticket checklist"""
        say(" Please put this check list into the ticket description:")
        show_link(ticket_url(self.state.yt_ticket))
        framed(ticket_template(self.state))
        acknowledge("Have you copied the checklist to the rescue ticket?")

    @step
    def set_out_of_service(self) -> None:
        """Set host out of service"""
        # Setting a node permanently out of service is not possible via the
        # directory API for now.
        operator_task(
            "You need to manually set the host `out of service` in the directory:",
            f"Did you set {self.hostname} out-of-service?",
            directory_url(self.hostname),
        )

    @step(always=True)
    def ensure_host_offline(self) -> None:
        """Fence off host"""
        if "cleanup_start" in self.state.completed:
            say("Main rescue is already finished, continuing…")
            return

        while True:
            if self.ipmi.is_powered_off():
                say("Host is safe to evacuate.", style="green")
                return

            say(f"""
 👩‍💻 You need to manually ensure the host is really down and/or cut off from the network.

 🚨 {self.hostname} MUST NOT BE REACHABLE 🚨

 Ideally you will now trigger a POWER OFF.

 If that does't work, you can still continue, because we will block pending Ceph connections
 in the next steps, but if Consul is still reachable, this will block VM evacuations.

 If the host is still visible in Consul and you can't power it down but
 can somehow SSH into it, then `systemctl stop consul` may help here.
""")

            # In practice, BMC connections can turn out to be rather flaky. But
            # retrying or deactivating-activating the SOL is left to the
            # operator.
            try:
                match Prompt.ask(
                    dedent("""
                    Actions:
                        1. Trigger IPMI [b]POWER OFF[/b]
                        2. Connect to [b]SOL[/b] console
                        3. Open ipmitool [b]shell[/b]
                        [dim]------------------------------------[/dim]
                        0. [b]continue[/b] anyway?

                    """),
                    choices=[
                        "1",
                        "power off",
                        "POWER OFF",
                        "2",
                        "SOL",
                        "3",
                        "shell",
                        "0",
                        "continue",
                    ],
                ):
                    case "1" | "power off":
                        self.ipmi.change("power", "off")
                    case "2" | "SOL":
                        self.ipmi.interactive("sol", "activate")
                    case "3" | "shell":
                        self.ipmi.interactive("shell")
                    case "4" | "continue" | _:
                        return
            except subprocess.CalledProcessError as e:
                say(str(e))

    @step
    def collect_locks(self) -> None:
        """Find affected RBD images"""
        pools = rbd_pools()
        say(f"Searching RBD pools: {', '.join(pools)}")
        # Listed up front so the bar below has a total: one `rbd ls` per pool is
        # cheap next to the `lock ls` per image that follows.
        images = [image for pool in pools for image in list_images(pool)]

        locked_images: dict[str, list[RbdLock]] = {}
        with progress_bar() as progress:
            task = progress.add_task(
                "Checking locks", total=len(images), item=""
            )
            for image in images:
                progress.update(task, item=image)
                locks = list_locks(image)
                progress.advance(task)
                if not any(lock.id == self.hostname for lock in locks):
                    continue
                if len(locks) > 1:
                    held_by = ", ".join(sorted(lock.id for lock in locks))
                    self.state.warn(
                        f"{image} is locked by {held_by}, but locking is expected to be exclusive."
                    )
                locked_images[image] = locks

        self.state.locked_images = locked_images
        self.state.save()

        say(f"Found {len(locked_images)} locked VM images.")

    @step
    def blocklist_lockers(self) -> None:
        """Blocklist current lockers"""
        # Breaking a lock blocklists the broken client by default. We do want
        # that, but with a longer TTL and for the full host, so we add the
        # entries explicitly beforehand.
        addresses = self.state.locker_addresses
        if not addresses:
            say("No known lockers, nothing to blocklist.")
        with progress_bar() as progress:
            task = progress.add_task(
                "Blocklisting", total=len(addresses), item=""
            )
            for address in addresses:
                progress.update(task, item=address)
                ceph(
                    "osd",
                    "blocklist",
                    "add",
                    address,
                    str(BLOCKLIST_TTL),
                    changes=True,
                )
                # Persisted one at a time, so entries already added do not get
                # lost when a later iteration fails.
                if address not in self.state.blocklist:
                    self.state.blocklist.append(address)
                    self.state.save()
                progress.advance(task)

    @step
    def break_locks(self) -> None:
        """Break affected locks"""
        if not self.state.locked_images:
            say("No known locked images, no locks to break.")
        with progress_bar() as progress:
            task = progress.add_task(
                "Breaking locks", total=len(self.state.locked_images), item=""
            )
            for image, locks in self.state.locked_images.items():
                progress.update(task, item=image)
                for lock in locks:
                    if lock.id != self.hostname:
                        self.state.warn(
                            f"{image} is also locked by {lock.id}; left that lock alone, please check afterwards."
                        )
                        continue
                    rbd(
                        "lock",
                        "remove",
                        # Speeds up the process, and is fine because
                        # blocklist_lockers already added an entry.
                        "--rbd_blocklist_on_break_lock=false",
                        image,
                        lock.id,
                        lock.locker,
                        changes=True,
                    )
                progress.advance(task)

    @step
    def evacuate_vms(self) -> None:
        """Evacuate VMs to other hosts"""
        cmd = ["fc-directory", f"d.evacuate_vms('{self.hostname}')"]
        if DRY_RUN:
            show_command(cmd)
            return
        # Output is not captured: the operator wants to watch directory work.
        subprocess.run(cmd, check=True)

    @step(always=True)
    def monitor_affected_vms(self) -> None:
        """Monitor evacuated VM status"""
        if DRY_RUN:
            return
        affected = sorted(
            {vm_name(image) for image in self.state.locked_images}
        )
        if not affected:
            say(
                "No volumes were locked -> no VMs were affected -> no monitoring necessary."
            )
            return
        say(f"{len(affected)} VMs were running on {self.hostname}.")
        say()

        # The root volume is what says where a VM now lives, so it is also
        # what makes a VM watchable.
        roots = {
            vm_name(image): image
            for image in self.state.locked_images
            if image.endswith(".root")
        }
        vms = [name for name in affected if name in roots]
        for name in affected:
            if name not in roots:
                # A VM with no root volume should not exist, and would never
                # answer a ping either. Flag it for an operator instead of
                # waiting for it forever.
                self.state.warn(
                    f"{name} has no root volume among the locked images;"
                    " left it out of the monitoring, please check it by hand."
                )
        if not vms:
            say("No VM has a root volume to watch.", style="orange1")
            return

        say(VM_LEGEND, style="dim")

        progress = Progress(
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            MofNCompleteColumn(),
            TimeElapsedColumn(),
        )
        task = progress.add_task(" Healthy VMs", total=len(vms))

        # Live keeps the whole list in one redrawing block instead of
        # scrolling a screenful of VMs past the operator every round.
        with (
            VmMonitor(vms, roots, self.hostname) as monitor,
            Live(console=console, refresh_per_second=4) as live,
        ):
            while not monitor.all_healthy:
                monitor.tick()
                progress.update(task, completed=monitor.healthy_count)
                live.update(
                    Group(
                        progress, vm_overview(list(monitor.statuses.values()))
                    )
                )
                sleep(TICK_INTERVAL)

        say(f"\n All {len(vms)} VMs are back.", style="green")

    @step
    def cleanup_start(self) -> None:
        """Initiate cleanup"""
        say(
            dedent("""
            Host evacuation is done. The remaining steps are cleanup.

            To handle the immediate emergency, feel free to exit here and
            continue later.""")
        )
        self.state.save()  # for good measure
        if not confirm("Continue with cleanup?"):
            raise KeyboardInterrupt()

    @step
    def investigate_warnings(self) -> None:
        """Investigate warnings"""
        if not self.state.warnings:
            say("No warnings found.")
            return
        report_warnings(self.state)
        acknowledge("Did you investigate all warnings above?")

    @step(always=True)
    def cleanup_check_machine_is_clean(self) -> None:
        """Double-check host fence or VM absence"""

        while True:
            if self.ipmi.is_powered_off():
                say(
                    "Host is powered off, so it's safe to clean the blocklist.",
                    style="green",
                )
                return

            say("""
 🚨 POTENTIAL DISK CORRUPTION AHEAD 🚨

 👩‍💻 You need to manually ensure the host will not reconnect with old
    Qemu processes still running.

    Your options:

    1. Ensure the host is powered down (via IPMI POWER OFF)
    2. Connect to the host via SSH and ensure no VMs are running (`fc-qemu ls`)
""")
            console.print(
                "    [red]DO NOT CONTINUE IF YOU DID NOT VERIFY EITHER[/red]"
            )

            # In practice, BMC connections can turn out to be rather flaky. But
            # retrying or deactivating-activating the SOL is left to the
            # operator.
            try:
                match Prompt.ask(
                    dedent("""
                    Actions:
                        1. Trigger IPMI [b]POWER OFF[/b]
                        [dim]------------------------------------[/dim]
                        0. I checked that no VMs are running - [b]continue [orange1]on my risk[/orange1][/b]!

                    """),
                    choices=[
                        "1",
                        "power off",
                        "POWER OFF",
                        "0",
                        "continue",
                    ],
                ):
                    case "1" | "power off":
                        self.ipmi.change("power", "off")
                    case "0" | "continue" | _:
                        if confirm(
                            "Confirm that you have double checked that NO VMs are running on the host?"
                        ):
                            return
            except subprocess.CalledProcessError as e:
                say(str(e))

    @step
    def blocklist_cleanup(self) -> None:
        """Remove Ceph blocklist entries"""
        try:
            with progress_bar() as progress:
                task = progress.add_task(
                    "Removing block",
                    total=len(self.state.blocklist),
                    item="",
                )
                for address in self.state.blocklist:
                    progress.update(task, item=address)
                    cmd = blocklist_rm_command(address)
                    show_command(cmd)
                    if not DRY_RUN:
                        subprocess.run(
                            cmd, check=True, capture_output=True, text=True
                        )
                    progress.advance(task)
        except subprocess.CalledProcessError:
            say("Error running last command.", style="red")
            say(
                "Try executing them manually on a ceph mon host of this cluster."
            )
            if not confirm("Did you execute the command successfully?"):
                raise

    @step
    def mark_nonprod(self) -> None:
        """Mark host as non-production"""
        operator_task(
            f"Consider setting the KVM production use of {self.hostname} to `non-production`.",
            "Ready to continue?",
            directory_url(self.hostname),
        )

    @step
    def set_back_in_service(self) -> None:
        """Set host back in service"""
        operator_task(
            "You need to manually set the machine back in service in the directory.",
            "Did you set the machine back in service in the directory?",
            directory_url(self.hostname),
        )


# --- reporting --------------------------------------------------------------


def checkbox(text: str, checked: bool = False) -> str:
    return f"- [{'x' if checked else ' '}] {text.strip()}"


def ticket_template(state: RescueState) -> str:
    """The current rescue state as CommonMark, to paste into the YT ticket."""
    lines = [f"## `fc-kvmrescue` run on `{gethostname()}`:", ""]
    lines += [
        checkbox(step_doc(name), checked=name in state.completed)
        for name in STEPS
    ]
    lines.append("\n")

    if state.warnings:
        lines += [
            "### Warnings",
            "",
            "Things that looked off and should be investigated:",
        ]
        lines += [checkbox(warning) for warning in sorted(state.warnings)]
        lines.append("\n")

    return "\n".join(lines)


def report_warnings(state: RescueState) -> None:
    if not state.warnings:
        return
    heading(
        "Things that looked off and should be investigated:", style="yellow"
    )
    for warning in sorted(state.warnings):
        say(f"  - {warning}")


def list_steps(state: RescueState | None) -> None:
    completed = state.completed if state else []
    table = Table(
        title=f"[yellow]Rescue steps for [b]{state.kvmhostname if state else ''}[/b][/yellow]",
        title_justify="left",
        box=box.SIMPLE,
    )
    table.add_column("#", justify="right", style="dim")
    # The first columns get whatever they need, the docs absorb the squeeze.
    table.add_column("Description")
    table.add_column("Status", no_wrap=True)

    for position, name in enumerate(STEPS, start=1):
        if name in ALWAYS_RUN:
            status = "[yellow]pending[/yellow] [dim](always runs)[/dim]"
        elif name in completed:
            status = "[green]done[/green]"
        else:
            status = "[yellow]pending[/yellow]"
        table.add_row(str(position), step_doc(name), status)

    console.print(table)
    if state:
        report_warnings(state)


# --- command line -----------------------------------------------------------


def known_rescues() -> list[RescueState]:
    """Every rescue that still has a state file, most recent first."""
    states: list[RescueState] = []
    for path in sorted(STATE_DIR.glob("*.json")):
        try:
            states.append(RescueState.model_validate_json(path.read_text()))
        except (OSError, ValueError):
            # A half-written or outdated file must not stand between the
            # operator and a new rescue.
            say(f"Ignoring unreadable state file {path}.", style="orange1")
    return sorted(states, key=lambda state: state.created, reverse=True)


def show_known_rescues() -> None:
    """Remind the operator which rescues are already under way.

    Shown before asking for a hostname, so an interrupted rescue gets resumed
    by name instead of being started again from the top.
    """
    states = known_rescues()
    if not states:
        return
    table = Table(
        title="[yellow]Rescues in progress[/yellow]",
        title_justify="left",
        box=box.SIMPLE,
    )
    table.add_column("Host", no_wrap=True)
    table.add_column("Ticket", no_wrap=True)
    table.add_column("Started", no_wrap=True)
    table.add_column("Last completed step")
    for state in states:
        if state.completed:
            last = step_doc(state.completed[-1])
        else:
            last = "[dim]nothing yet[/dim]"
        table.add_row(
            state.kvmhostname,
            state.yt_ticket or "[dim]none[/dim]",
            f"{state.created:%Y-%m-%d %H:%M}",
            last,
        )
    console.print(table)


def open_state(kvmhostname: str | None) -> RescueState:
    """Find or start the state file for the host being rescued."""
    if not kvmhostname:
        show_known_rescues()
    while not kvmhostname:
        kvmhostname = Prompt.ask("Enter hostname of the KVM host to evacuate")

    state = RescueState.load(kvmhostname)
    if state is None:
        return new_state(kvmhostname)

    console.print(
        f"Found existing rescue state from {state.created:%Y-%m-%d %H:%M %Z} at {state.path}.\n",
        style="dim",
    )
    list_steps(state)
    if confirm(f"Continue rescue for [b]{state.kvmhostname}[/b]?"):
        return state

    return new_state(kvmhostname)


def new_state(kvmhostname: str) -> RescueState:
    state = RescueState(
        kvmhostname=kvmhostname,
        created=datetime.now(tz=UTC),
    )
    state.save()
    say(f"Created new state file at {state.path}")
    return state


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rescue the VMs of a dead KVM host.",
        epilog="Without a step, the whole sequence runs; steps already recorded as done skip themselves, so this doubles as resuming an interrupted rescue.",
    )
    parser.add_argument(
        "kvmhostname",
        nargs="?",
        help="hostname of the KVM host to evacuate (asked for if omitted)",
    )
    parser.add_argument("--step", choices=STEPS, help="run only this step")
    parser.add_argument(
        "--list",
        action="store_true",
        dest="list_steps",
        help="show the steps and what has already run, then exit",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the commands that would change the cluster or the host"
        " instead of running them, and write no state file",
    )
    parser.add_argument(
        "--no-skip",
        action="store_false",
        dest="skip",
        help="run steps even if they are already recorded as done",
    )
    return parser.parse_args(argv)


def run_rescue(argv: list[str]):
    global DRY_RUN
    args = parse_args(argv[1:])
    DRY_RUN = args.dry_run  # pyright: ignore[reportConstantRedefinition]

    if args.list_steps:
        state = RescueState.load(args.kvmhostname) if args.kvmhostname else None
        if args.kvmhostname and state is None:
            say(
                "Unable to load state file. Showing an empty run.",
                style="orange1",
            )
        list_steps(state)
        return 0

    state = open_state(args.kvmhostname)
    rescue = Rescue(state)
    resume = f"Run `{argv[0]} {state.kvmhostname}` to continue."
    if DRY_RUN:
        say(
            dedent("""
            Dry run: nothing is changed and no state is written.

            The operator prompts still run, so you can walk the whole
            sequence.
            """),
            style="cyan",
        )

    todo = STEPS
    skip = args.skip
    if args.step:
        # A single step is always run deliberately, so nothing is skipped.
        todo, skip = [args.step], False
        missing = [
            name
            for name in STEPS[: STEPS.index(args.step)]
            if name not in state.completed
        ]
        if missing:
            say(
                f"{args.step} requires steps that have not run yet:",
                style="red",
            )
            for position, name in enumerate(missing, start=1):
                say(f"  {position}. {name}")
            say(resume)
            return 1

    divider()

    try:
        for name in todo:
            step_id = STEPS.index(name) + 1
            if skip and name in state.completed and name not in ALWAYS_RUN:
                console.print(
                    f"✅ [b][green]Step {step_id}/{len(STEPS)} {step_doc(name)}[/green][/b] (skipped, already done)"
                )
                divider()
                continue
            console.print(
                f"📋 [b]Step {step_id}/{len(STEPS)} {step_doc(name)}\n",
            )
            getattr(rescue, name)()
            # Only reached when the step returned normally, so a step that
            # raised stays unrecorded and a later run picks it up again.
            state.mark_done(name)
            divider()
        if args.step:
            say(f"Finished step {args.step}.")
            following = STEPS[STEPS.index(args.step) + 1 :]
            if following:
                say(f"Next step to invoke manually would be {following[0]}.")
    except KeyboardInterrupt:
        say(f"Interrupted. {resume}")
    finally:
        report_warnings(state)
        heading("Update the rescue ticket as follows:")
        if state.yt_ticket:
            show_link(ticket_url(state.yt_ticket))
        framed(ticket_template(state))


def main() -> None:
    """Entry point of both the uv script and the installed `fc-kvmrescue`."""
    run_rescue(sys.argv)


if __name__ == "__main__":
    main()
