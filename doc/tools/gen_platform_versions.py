"""Generate the version-switcher payload ``src/_static/platform-versions.js``.

Two inputs, both on disk and strictly local:

* ``platform-versions.toml`` -- the declared version set. The entry
  whose ``rev`` is the repo's ACTIVE bookmark (:func:`match_active`)
  is the LOCAL manual: it builds at ``/`` and is never checked out,
  whatever its category. Every other entry -- including a non-matched
  ``[current]`` -- is placed as a snapshot under ``src/<ver>/`` by
  ``tools/checkout_versioned_docs.py`` (each builds at ``/<ver>/``).

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
import subprocess
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

# The hg repository that carries the version bookmarks: doc/'s parent.
REPO_ROOT = DOC_ROOT.parent

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


class ActiveBookmarkError(RuntimeError):
    """The repo's active bookmark cannot identify the local manual."""


def active_bookmark(repo: Path) -> str:
    """The repo's ACTIVE bookmark name (``''`` when none is active).

    ``hg log -r . -T {activebookmark}`` reads exactly what ``hg su``
    (summary) reports as active: the bookmark the working dir sits on
    AND advances on commit. Updating to a bare rev deactivates it.
    """
    proc = subprocess.run(
        ["hg", "log", "-r", ".", "-T", "{activebookmark}"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        msg = (
            f"cannot read the active bookmark of {repo} ({proc.stderr.strip()})"
            " -- is it an hg working directory?"
        )
        raise ActiveBookmarkError(msg)
    return proc.stdout.strip()


def match_active(versions: VersionSet, repo: Path) -> VersionEntry:
    """The declared entry whose ``rev`` is the repo's ACTIVE bookmark.

    That entry IS the local manual: it builds at ``/`` and is never
    checked out, whatever its TOML category. No active bookmark, or one
    unknown to the TOML, is an error -- there is NO fallback to any
    category: guessing would silently build the wrong manual at ``/``.
    """
    bookmark = active_bookmark(repo)
    if not bookmark:
        msg = (
            f"no active bookmark in {repo} -- the ACTIVE bookmark selects "
            "the local manual: hg up <bookmark> to activate one (verify "
            "with hg su); there is no fallback"
        )
        raise ActiveBookmarkError(msg)
    for entry in versions.entries():
        if entry.rev == bookmark:
            return entry
    known = ", ".join(entry.rev for entry in versions.entries())
    msg = (
        f"active bookmark {bookmark!r} matches no rev in "
        f"platform-versions.toml (known revs: {known}) -- hg up one of "
        "them or declare the rev"
    )
    raise ActiveBookmarkError(msg)


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


def build_payload(
    versions: VersionSet, matched: VersionEntry, src_root: Path
) -> dict:
    """Build the switcher payload with ``matched`` as the local manual.

    ``matched`` (the entry whose rev is the ACTIVE bookmark, see
    :func:`match_active`) builds at ``/``: the local ``src/`` tree IS
    its inventory. Every OTHER declared entry -- including a
    non-matched ``[current]`` -- is a snapshot at ``/<ver>/`` whose
    inventory is scanned from ``src/<ver>/``. Missing snapshots of
    declared versions and orphan snapshot dirs of undeclared versions
    are warned about, never fatal -- the payload is still complete
    enough to build with (empty ``pages``), and ``make
    checkout-versioned-docs`` is the fix for both.
    """
    entries = versions.entries()

    inventories: dict[str, set[str] | None] = {}
    for entry in entries:
        if entry.ver == matched.ver:
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
        index = "/" if entry.ver == matched.ver else f"/{entry.ver}/"
        payload_versions.append(
            {
                "ver": entry.ver,
                "label": entry.label,
                "status": entry.status,
                "index": index,
                "pages": {
                    page_id: index for page_id in sorted(inventory & versioned)
                },
            }
        )
    return {"current": matched.ver, "versions": payload_versions}


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
    (unreadable src/, or no/unknown active bookmark), ``2`` (invalid
    platform-versions.toml).
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
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
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

    try:
        matched = match_active(versions, args.repo)
    except ActiveBookmarkError as exc:
        log.error(
            "active-bookmark-unmatched",
            repo=str(args.repo),
            error=str(exc),
        )
        return 1
    log.info(
        "active-bookmark-matched",
        ver=matched.ver,
        rev=matched.rev,
        status=matched.status,
    )

    payload = build_payload(versions, matched, args.src)
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
