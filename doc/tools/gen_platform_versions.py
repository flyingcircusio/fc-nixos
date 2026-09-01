"""Generate the version-switcher payload ``src/_static/platform-versions.js``.

Two inputs, both on disk and strictly local:

* ``platform-versions.toml`` -- the declared version set. ``[current]`` is
  the LOCAL tree by definition: it builds at ``/`` and is never checked
  out. ``[[prerelease]]`` and ``[[sunsetting]]`` name versions that
  ``tools/checkout_versioned_docs.py`` places as full snapshots under
  ``src/<ver>/`` (each builds at ``/<ver>/``).

* the file trees -- the local ``src/`` tree plus every ``src/<ver>/``
  snapshot. A page is identified by its URL-shaped page-id
  (tree-relative path sans ``.md``, trailing ``index`` folded away:
  ``getting-started/index.md`` -> ``getting-started``). The scan is
  content-agnostic: WHAT a page contains never matters, only WHETHER
  the file exists in a tree. Snapshot dirs never leak into the local
  inventory: top-level ``src/<NN.NN>/`` dirs are skipped when scanning
  the current version.

A page-id found in at least TWO trees is *versioned*: every version
carrying it gets a ``pages`` entry mapping the page-id to its URL
prefix -- the data same-page switching is built from. A page-id that
exists in only one tree is a common page and gets no switcher entry at
all.

The output file is COMMITTED (generated, never hand-edited). Regenerate
via ``make gen-platform-versions`` after changing the TOML or after
``make checkout-versioned-docs``.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import tomllib
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import structlog

log = structlog.get_logger()

# doc/ root -- defaults resolve relative to the module, not the cwd, so
# the tool works from any directory (the Makefile runs it from doc/).
DOC_ROOT = Path(__file__).resolve().parents[1]

# Version format everywhere: two digits, dot, two digits (``26.05``).
VERSION_RE = re.compile(r"\d{2}\.\d{2}")


def is_version_dir(name: str) -> bool:
    """True for top-level src/ children that hold a version snapshot."""
    return bool(VERSION_RE.fullmatch(name))


@dataclass(frozen=True, slots=True)
class VersionEntry:
    """One declared version: where it comes from and how it is served.

    ``rev`` is the hg bookmark ``checkout_versioned_docs`` resolves --
    purely informational here, this tool never touches the repository.
    """

    ver: str
    rev: str
    status: str  # "current" | "prerelease" | "sunsetting"

    @property
    def index(self) -> str:
        """URL prefix of the version -- also the per-page href prefix."""
        return "/" if self.status == "current" else f"/{self.ver}/"

    @property
    def label(self) -> str:
        return f"{self.ver} ({self.status})"


@dataclass(frozen=True, slots=True)
class VersionSet:
    """The declared versions in canonical order: current, then the rest."""

    current: VersionEntry
    prereleases: tuple[VersionEntry, ...] = ()
    sunsettings: tuple[VersionEntry, ...] = ()

    def entries(self) -> list[VersionEntry]:
        return [self.current, *self.prereleases, *self.sunsettings]


def _entry(section: str, raw: object, path: Path) -> VersionEntry:
    """Validate one TOML section into a :class:`VersionEntry`."""
    if not isinstance(raw, dict):
        msg = f"[{section}] must be a table, got {type(raw).__name__}"
        raise ValueError(msg)
    ver = raw.get("ver")
    rev = raw.get("rev")
    if not isinstance(ver, str) or not VERSION_RE.fullmatch(ver):
        msg = f"[{section}] ver must match NN.NN, got {ver!r}"
        raise ValueError(msg)
    if not isinstance(rev, str) or not rev:
        msg = f"[{section}] rev must be a non-empty string, got {rev!r}"
        raise ValueError(msg)
    return VersionEntry(
        ver=ver, rev=rev, status="current" if section == "current" else section
    )


def load_versions(path: Path) -> VersionSet:
    """Parse and validate ``platform-versions.toml``.

    Raises :class:`ValueError` with a section-context message on any
    schema violation (missing ``[current]``, malformed ver, duplicate
    ver across sections).
    """
    with path.open("rb") as fh:
        data = tomllib.load(fh)

    if "current" not in data:
        msg = f"missing [current] section in {path.name}"
        raise ValueError(msg)

    entries = [_entry("current", data["current"], path)]
    for section in ("prerelease", "sunsetting"):
        for raw in data.get(section, []):
            entries.append(_entry(section, raw, path))

    seen: set[str] = set()
    for entry in entries:
        if entry.ver in seen:
            msg = f"duplicate ver {entry.ver!r} in {path.name}"
            raise ValueError(msg)
        seen.add(entry.ver)

    return VersionSet(
        current=entries[0],
        prereleases=tuple(e for e in entries[1:] if e.status == "prerelease"),
        sunsettings=tuple(e for e in entries[1:] if e.status == "sunsetting"),
    )


def page_id(rel: Path) -> str:
    """URL-shaped page-id for a tree-relative ``*.md`` path.

    ``.md`` is stripped and a trailing ``index`` component is folded
    away: ``getting-started/index.md`` is page-id ``getting-started``
    because zensical serves it at ``/getting-started/`` -- ids must
    match the URLs the switcher concatenates (``<prefix><page-id>/``,
    also in version-switcher-fallback.js).
    """
    parts = list(rel.with_suffix("").parts)
    if parts and parts[-1] == "index":
        parts.pop()
    return "/".join(parts)


def scan_page_ids(tree: Path, *, exclude_snapshots: bool = False) -> set[str]:
    """All page-ids below *tree* (URL-shaped, see :func:`page_id`).

    With ``exclude_snapshots`` top-level snapshot dirs (``tree/26.05/``)
    are skipped -- that is how the LOCAL tree is scanned, so snapshots
    never appear as ``26.05/...`` page-ids of the current version.
    """
    ids: set[str] = set()
    for page in tree.rglob("*.md"):
        rel = page.relative_to(tree)
        if exclude_snapshots and is_version_dir(rel.parts[0]):
            continue
        ids.add(page_id(rel))
    return ids


def build_payload(versions: VersionSet, src_root: Path) -> dict:
    """Build the switcher payload from the TOML set and the file trees.

    Pure-local: reads ``src/`` and ``src/<ver>/`` only. Missing
    snapshots of declared versions and orphan snapshot dirs of
    undeclared versions are warned about, never fatal -- the payload is
    still complete enough to build with (empty ``pages``), and
    ``make checkout-versioned-docs`` is the fix for both.
    """
    entries = versions.entries()

    inventories: dict[str, set[str] | None] = {}
    for entry in entries:
        if entry.status == "current":
            inventories[entry.ver] = scan_page_ids(
                src_root, exclude_snapshots=True
            )
            continue
        snapshot = src_root / entry.ver
        if snapshot.is_dir():
            inventories[entry.ver] = scan_page_ids(snapshot)
        else:
            inventories[entry.ver] = None
            log.warning(
                "snapshot-missing",
                ver=entry.ver,
                expected=str(snapshot),
                hint="run make checkout-versioned-docs",
            )

    declared = {entry.ver for entry in entries}
    if src_root.is_dir():
        for child in sorted(src_root.iterdir()):
            if (
                child.is_dir()
                and is_version_dir(child.name)
                and child.name not in declared
            ):
                log.warning(
                    "orphan-snapshot-dir",
                    ver=child.name,
                    path=str(child),
                    hint="not declared in platform-versions.toml; checkout-versioned-docs prunes it",
                )

    known = set().union(*(inv for inv in inventories.values() if inv))
    versioned = {
        page_id
        for page_id in known
        if sum(1 for inv in inventories.values() if inv and page_id in inv) >= 2
    }

    payload_versions = []
    for entry in entries:
        inventory = inventories[entry.ver] or set()
        payload_versions.append(
            {
                "ver": entry.ver,
                "label": entry.label,
                "status": entry.status,
                "index": entry.index,
                "pages": {
                    page_id: entry.index
                    for page_id in sorted(inventory & versioned)
                },
            }
        )
    return {"current": versions.current.ver, "versions": payload_versions}


GENERATED_HEADER = (
    "/* Generated by tools/gen_platform_versions.py -- do not edit.\n"
    " * Source: platform-versions.toml + src/ file trees (make gen-platform-versions). */"
)


def render_js(payload: dict) -> str:
    """Render the payload as the committed ``platform-versions.js``."""
    body = json.dumps(payload, indent=2, ensure_ascii=False)
    return f"{GENERATED_HEADER}\nwindow.PLATFORM_VERSIONS = {body};\n"


# Minimum log level for the CLI (matches logging.INFO; the int literal keeps
# the tool free of an ``import logging`` per the project's structlog-only rule).
_INFO_LEVEL = 20


def _configure_logging() -> None:
    """Render human-readable diagnostics to stderr.

    stderr, resolved at call time: ``make`` surfaces a failing
    prerequisite's stderr verbatim while stdout stays clean for
    zensical -- and pytest's capsys captures it (capture_logs around
    ``main()`` does NOT work: this reconfiguration clobbers it).
    """
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.add_log_level,
            structlog.dev.ConsoleRenderer(colors=False),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(_INFO_LEVEL),
        logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
    )


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry: ``python -m tools.gen_platform_versions``.

    Exit codes: ``0`` (payload written, or already up to date), ``1``
    (unreadable src/), ``2`` (invalid platform-versions.toml).
    """
    _configure_logging()
    parser = argparse.ArgumentParser(
        prog="gen_platform_versions",
        description="Generate src/_static/platform-versions.js from platform-versions.toml and the src/ file trees.",
    )
    parser.add_argument(
        "--versions", type=Path, default=DOC_ROOT / "platform-versions.toml"
    )
    parser.add_argument("--src", type=Path, default=DOC_ROOT / "src")
    parser.add_argument(
        "--out",
        type=Path,
        default=DOC_ROOT / "src" / "_static" / "platform-versions.js",
    )
    args = parser.parse_args(argv)

    try:
        versions = load_versions(args.versions)
    except ValueError as exc:
        log.error("versions-invalid", path=str(args.versions), error=str(exc))
        return 2

    if not args.src.is_dir():
        log.error("src-missing", src=str(args.src))
        return 1

    payload = build_payload(versions, args.src)
    rendered = render_js(payload)
    if args.out.exists() and args.out.read_text() == rendered:
        versioned = len({p for v in payload["versions"] for p in v["pages"]})
        log.info(
            "gen-platform-versions-unchanged",
            out=str(args.out),
            versions=len(payload["versions"]),
            versioned_pages=versioned,
        )
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered)
    versioned = len({p for v in payload["versions"] for p in v["pages"]})
    log.info(
        "gen-platform-versions-done",
        out=str(args.out),
        versions=len(payload["versions"]),
        versioned_pages=versioned,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
