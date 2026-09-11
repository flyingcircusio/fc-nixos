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


class Ipmitool:
    # Implement mlock to avoid swapping as we store sensitive data (like encryption)
    # keys.
    # Constants defined by kernel, not dynamically accessible here:
    # https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tree/include/uapi/asm-generic/mman.h#n18

    MCL_CURRENT: ClassVar[int] = 1
    MCL_FUTURE: ClassVar[int] = 2

    hostname: str

    _ipmipw: str | None = None
    _ipmiuser: str | None = None

    libc: ClassVar[ctypes.CDLL] = ctypes.CDLL("libc.so.6", use_errno=True)

    def __init__(self, hostname: str) -> None:
        self.hostname = hostname

    @classmethod
    def mlockall(cls) -> None:
        result = cast(int, cls.libc.mlockall(cls.MCL_CURRENT | cls.MCL_FUTURE))
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

    def __init__(self, kvmhostname: str) -> None:
        state, pre_existing = RescueState.ensure_statefile(
            kvmhostname=kvmhostname
        )
        recreate = False
        if pre_existing and state.kvmhostname != kvmhostname:
            print(
                f"[orange1]Found existing rescue state file for host {state.kvmhostname} from {state.creation_date}. Starting over with new state."
            )
            recreate = True
        if pre_existing and state.kvmhostname == kvmhostname:
            recreate = not Confirm.ask(
                f"Found existing rescue-state from {state.creation_date}. Continue using that data?"
            )
        if recreate:
            state.move_aside()
            state = RescueState.new_state(kvmhostname=kvmhostname)
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
        return Ipmitool(self.kvmhostname)

    # -- steps, in the order they run --------------------------------------

    @step()
    def set_out_of_service(self) -> None:
        """Have the operator take the host out of service in the directory."""
        # Setting a node permanently out of service is not possible via
        # directory API for now
        url = f"https://directory.fcio.net/machine/list?search=name-{self.kvmhostname}"
        print(" > Set the host out of service in the directory:")
        # As an explicit OSC 8 hyperlink, so the terminal does not have to guess
        # where the URL ends -- iTerm's own detection ran it into the following
        # prompt. On its own line for terminals that lack OSC 8 and do guess.
        print(f"   [link={url}]{url}[/link]")
        print()
        while not Confirm.ask(
            f"[purple]Is host {self.kvmhostname} set out-of-service?"
        ):
            pass

    @step(skip=False)
    def ensure_host_offline(self) -> None:
        """Establish that the host is really down before touching its locks."""
        try:
            power_status = self.ipmi(
                "power", "status", capture_output=True
            ).stdout.strip()

            if power_status == "Chassis Power is off":
                # we can force-unlock all the collected images
                return
        except subprocess.CalledProcessError as e:
            print(f"Error calling ipmitool: {escape(str(e))}")
        else:
            print(
                f"{self.kvmhostname} status is '{escape(power_status)}', please ensure it is not running any VMs before continuing."
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
                        _ = self.ipmi("sol", "activate", tty=True)
                    case "shell":
                        print("Opening an [i]ipmitool shell[/i]")
                        _ = self.ipmi("shell", tty=True)
                    case "continue":
                        print(
                            f"[yellow]If {self.kvmhostname} is not reliably down this may corrupt VM images. If there is any doubt, consider disconnecting the host from the Ceph cluster at network level."
                        )
                    case _:
                        print("[orange1]Invalid choice.")
                        continue
            except subprocess.CalledProcessError as e:
                print(escape(str(e)))
            if Confirm.ask(
                f"Did you ensure that {self.kvmhostname} is reliably down?"
            ):
                break

    @step()
    def collect_locks(self) -> None:
        """Find the VM images the dead host still holds Ceph locks on."""
        # - tote VMs anhand von Ceph Lock identifizieren:
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

        print(locked_images)

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

    @step(skip=False)
    def report_blocklist_cleanup(self) -> None:
        """Print the script that removes those blocklist entries again."""
        # Not skippable: it only reads persisted state, and wanting the script
        # back is a perfectly good reason to re-run the tool.
        print()
        print(
            f"Blocklisted the current locker addresses of {self.kvmhostname}.\n"
            + "Once the dead host has recovered, execute the following script on a [b]ceph mon[/b] host of this cluster:"
        )
        print("[purple]" + "=" * 80 + "[/purple]")
        print(
            "\n".join(
                plain(entry.cleanup_command)
                for entry in self.state.blocklist_entries
            )
        )
        print("[purple]" + "=" * 80 + "[/purple]")

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
        """Hand the VMs over to the directory for evacuation."""
        # - finally evacuate all VMs away
        _ = subprocess.run(["fc-directory", f"d.evacuate_vms('{self.kvmhostname}')"], check=True)  # fmt: skip


def report_warnings(state: RescueState) -> None:
    if not state.warnings:
        return
    print()
    print("[yellow]Things that looked off and should be investigated:")
    for warning in state.warnings:
        print(f"  - {plain(warning)}")


def list_steps(kvmhostname: str) -> int:
    state = RescueState.load()
    if state is not None and state.kvmhostname != kvmhostname:
        print(
            f"[orange1]The state file belongs to {state.kvmhostname}, not {kvmhostname}. Showing an empty run."
        )
        state = None
    completed = state.completed if state else []

    table = Table(
        title=f"Rescue steps for {kvmhostname}",
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

    kvmhostname: str  # pyright: ignore[reportUninitializedInstanceVariable]
    step: str | None  # pyright: ignore[reportUninitializedInstanceVariable]
    list_steps: bool  # pyright: ignore[reportUninitializedInstanceVariable]
    skip: bool  # pyright: ignore[reportUninitializedInstanceVariable]


def parse_args(argv: list[str]) -> Args:
    parser = argparse.ArgumentParser(
        description="Rescue the VMs of a dead KVM host.",
        epilog="Without a step, the whole sequence runs; steps already recorded as done skip themselves, so this doubles as resuming an interrupted rescue.",
    )
    _ = parser.add_argument("kvmhostname", help="the dead KVM host")
    _ = parser.add_argument(
        "step",
        nargs="?",
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
    args = parse_args(argv)

    if args.list_steps:
        return list_steps(args.kvmhostname)

    rescue = KVMHostRescue(args.kvmhostname)

    start: StepDef | None = None
    if args.step:
        start = STEPS_BY_NAME[args.step]
        missing = missing_prerequisites(start, rescue.state.completed)
        if missing:
            print(
                f"[red]{start.name} requires steps that have not run yet:[/red]"
            )
            for position, definition in enumerate(missing, start=1):
                print(f"  {position}. {definition.name}")
            print(
                f"Run `fc-kvmrescue {rescue.kvmhostname}` to work through the sequence from where it stopped."
            )
            return 1

    try:
        for rstep in run(rescue, start, skip=args.skip):
            if rstep.skipped:
                print(f"[dim]skip {rstep.definition.name} (already done)[/dim]")
            else:
                print()
                print(f"[b]{rstep.definition.name}[/b]: {rstep.definition.doc}")
            rstep()
            if args.step:
                break
    except RescueDone as done:
        print(f"[green]{plain(str(done))}[/green]")
        if "set_out_of_service" in rescue.state.completed:
            # Ending early leaves that first step's effect in place, and nothing
            # later undoes it.
            print(
                f"[yellow]Note: {rescue.kvmhostname} is still set out-of-service."
            )
        report_warnings(rescue.state)
        return 2

    report_warnings(rescue.state)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
