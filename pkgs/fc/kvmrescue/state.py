"""Persisted state for fc-kvmrescue.

Everything a rescue step gathers lands here and is written out after step completion, so
an interrupted rescue can be resumed.

The data models also live here due to import shaping.
"""

import re
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, ClassVar, Self, override

from pydantic import (
    BaseModel,
    BeforeValidator,
    ConfigDict,
    IPvAnyAddress,
    PlainSerializer,
    model_validator,
)
from rich import print

STATE_FILE_PATH = Path.home() / Path(".local/state/fc-kvmrescue/state.json")


# frozen to stay hashable, so imagespecs can be collected in sets
@dataclass(frozen=True)
class RbdImageSpec:
    pool: str
    imagename: str
    # in principle, snapshots are also part of an imagespec, but not relevant here
    # namespaces are also not considered for now, we only gather data from the default namespace.

    @override
    def __str__(self) -> str:
        return f"{self.pool}/{self.imagename}"


def parse_imagespec(value: object) -> object:
    # Accepts the `pool/imagename` form we serialize to, and passes anything
    # else through for pydantic to validate as the dataclass itself.
    if not isinstance(value, str):
        return value
    pool, separator, imagename = value.partition("/")
    if not (separator and pool and imagename):
        raise ValueError(f"not a `pool/imagename` spec: {value!r}")
    return RbdImageSpec(pool=pool, imagename=imagename)


# Serialized as `rbd.hdd/vm-alpha` rather than as an object, so it can be used
# as a JSON key -- and so the state file resembles full imagespec paths
ImageSpec = Annotated[
    RbdImageSpec,
    BeforeValidator(parse_imagespec),
    PlainSerializer(str, return_type=str),
]


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
    def parse(cls, value: object) -> object:
        # Accept both the string form found in `rbd` output and an already
        # structured mapping -- the latter is what we read back from the state
        # file.
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


def locks_held_by(locks: list[RbdLock], kvmhostname: str) -> list[RbdLock]:
    return [lock for lock in locks if lock.id == kvmhostname]


def foreign_locks(locks: list[RbdLock], kvmhostname: str) -> list[RbdLock]:
    return [lock for lock in locks if lock.id != kvmhostname]


class BlocklistEntry(BaseModel):
    """An osd blocklist entry we added, and how to get rid of it again."""

    # frozen to stay hashable, so entries can be collected in a set
    model_config: ClassVar[ConfigDict] = ConfigDict(frozen=True)

    address: str  # already in the `<addr>:0/0` blocklist form

    @property
    def cleanup_command(self) -> str:
        return f"ceph osd blocklist rm {self.address}"


class RescueState(BaseModel):
    creation_date: datetime
    kvmhostname: str
    completed: list[str] = []
    # Every lock found on an image the dead host holds a lock on. Including foreign
    # locks as well, since those indicate an image wants a second look by an operator.
    locked_images: dict[ImageSpec, list[RbdLock]] = {}
    blocklist_entries: set[BlocklistEntry] = set()
    # Anything that looked off while stepping through, to be presented to the
    # operator as a check list at the end instead of scrolling back.
    warnings: set[str] = set()

    @classmethod
    def load(cls) -> Self | None:
        """Read the state file without prompting, if there is one."""
        try:
            return cls.model_validate_json(STATE_FILE_PATH.read_text())
        except FileNotFoundError:
            return None

    @classmethod
    def ensure_statefile(cls, kvmhostname: str) -> tuple[Self, bool]:
        state = cls.load()
        if state is None:
            return (cls.new_state(kvmhostname=kvmhostname), False)
        return (state, True)

    @classmethod
    def new_state(cls, kvmhostname: str) -> Self:
        # Only persisted with `save` once there is something worth saving.
        return cls(kvmhostname=kvmhostname, creation_date=datetime.now(tz=UTC))

    def save(self) -> None:
        STATE_FILE_PATH.parent.mkdir(parents=True, exist_ok=True)
        _ = STATE_FILE_PATH.write_text(self.model_dump_json(indent=2))

    def mark_done(self, stepname: str) -> None:
        if stepname not in self.completed:
            self.completed.append(stepname)
        self.save()

    def warn(self, message: str) -> None:
        self.warnings.add(message)
        self.save()

    @property
    def locker_addresses(self) -> set[IPvAnyAddress]:
        """The addresses the dead host locks from -- never a foreign locker's."""
        return {
            lock.address.ip
            for locks in self.locked_images.values()
            for lock in locks_held_by(locks, self.kvmhostname)
        }

    @staticmethod
    def move_aside() -> None:
        target = STATE_FILE_PATH.parent / "state.json.old"
        print(f"Moving old state file to {target}.")
        _ = STATE_FILE_PATH.rename(target=target)
