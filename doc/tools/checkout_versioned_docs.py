"""Place version snapshots under ``src/<ver>/`` from LOCAL hg revisions.

The counterpart of ``tools.gen_platform_versions.py``: for every
``[[prerelease]]`` and ``[[sunsetting]]`` entry in
``platform-versions.toml`` this tool resolves ``rev`` -- an hg bookmark
-- STRICTLY locally (``hg log -r <rev>``, no network, no pull) and
exports that revision's docs into ``src/<ver>/``. ``[current]`` is
never checked out: the local tree IS the current version.

What gets exported depends on the status: prerelease revisions export
the WHOLE ``doc/src/**``; sunsetting revisions ONLY their branch's
namespaced ``doc/src/<ver>/**`` (the one-time sunset move commit). A
sunsetting revision without that namespaced tree fails loudly with the
remediation -- it NEVER falls back to the whole tree, which would
duplicate the current manual under a versioned URL.

Snapshots are dumb, content-agnostic trees: whatever the exported
subtree contains gets placed as-is. The only processing is for
``sunsetting`` versions, whose pages receive ``search: exclude``
frontmatter (keeping them out of the search index) and a warning
banner linking the current counterpart when it exists.

A manifest (``src/.checkout-manifest.json``) records the exported node
per version plus this tool's sha256. A version is skipped when BOTH
are unchanged -- re-running never clobbers the placed tree, and editing
this tool re-places every version (banner/frontmatter logic may have
changed). Undeclared ``src/<NN.NN>/`` dirs are pruned.

Regenerate via ``make checkout-versioned-docs`` (then
``make gen-platform-versions`` to refresh the switcher payload).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path

import structlog

from tools.gen_platform_versions import DOC_ROOT, VersionEntry, load_versions

log = structlog.get_logger()

# The hg repository that carries the version bookmarks: doc/'s parent.
REPO_ROOT = DOC_ROOT.parent

# Only doc/src of a revision becomes a snapshot: the whole tree for a
# prerelease, just the namespaced subtree for a sunsetting version.
ARCHIVE_INCLUDE = "doc/src/**"


def namespaced_include(ver: str) -> str:
    """Archive include pattern for a sunsetting version's subtree."""
    return f"doc/src/{ver}/**"


# Manifest lives (hidden) at the src/ root, beside the snapshot dirs.
MANIFEST_NAME = ".checkout-manifest.json"

# `search:` key in frontmatter (nested form: `search:\n  exclude: true`)
SEARCH_KEY_RE = re.compile(r"(?m)^search:")

SEARCH_EXCLUDE_BLOCK = "search:\n  exclude: true\n"


class CheckoutError(RuntimeError):
    """A version could not be resolved or exported -- fail loudly."""


def resolve_node(repo: Path, rev: str) -> str:
    """Resolve ``rev`` to a node hash, strictly locally.

    Missing bookmarks raise :class:`CheckoutError` with the hg abort
    message -- the caller must surface it, the user must pull. This
    tool never touches the network.
    """
    proc = subprocess.run(
        ["hg", "log", "-r", rev, "-T", "{node}"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        msg = (
            f"cannot resolve rev {rev!r} locally ({proc.stderr.strip()}) -- "
            "pull the bookmark into your clone yourself; this tool never pulls"
        )
        raise CheckoutError(msg)
    return proc.stdout.strip()


def tool_fingerprint() -> str:
    """sha256 of this file -- forces re-placement when the tool changes."""
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def load_manifest(path: Path) -> dict:
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


def write_manifest(path: Path, manifest: dict) -> None:
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def ensure_sunsetting_tree(repo: Path, entry: VersionEntry, node: str) -> None:
    """Fail loudly when the revision lacks ``doc/src/<ver>/``.

    A sunsetting ``rev`` must point at the sunset move commit that
    namespaced ``doc/src`` into ``doc/src/<ver>/``. A revision without
    that tree (e.g. a pre-move changeset carrying the whole ``doc/src``)
    must NEVER fall back to it -- the snapshot would duplicate the
    current manual under a versioned URL. ``hg files`` with an explicit
    ``path:`` kind asks hg directly whether the tree exists at *node*;
    empty output means it does not.
    """
    proc = subprocess.run(
        ["hg", "files", "-r", node, f"path:doc/src/{entry.ver}"],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        msg = (
            f"sunsetting revision {node[:12]} for ver {entry.ver} has no "
            f"doc/src/{entry.ver}/ tree -- point rev at the sunset move "
            f"commit that namespaced doc/src into doc/src/{entry.ver}/; "
            f"pre-move revisions carry the whole doc/src tree and are "
            f"never a fallback"
        )
        raise CheckoutError(msg)


def checkout_version(
    repo: Path, src_root: Path, entry: VersionEntry, node: str
) -> Path:
    """Export ``node``'s docs as ``src_root/<ver>/`` (replacing any old tree).

    Prerelease revisions export the WHOLE ``doc/src/**``; sunsetting
    revisions only their branch's namespaced ``doc/src/<ver>/**`` (see
    :func:`ensure_sunsetting_tree`).
    """
    if entry.status == "sunsetting":
        ensure_sunsetting_tree(repo, entry, node)
        include = namespaced_include(entry.ver)
        exported_subtree = Path("doc") / "src" / entry.ver
    else:
        include = ARCHIVE_INCLUDE
        exported_subtree = Path("doc") / "src"
    with tempfile.TemporaryDirectory() as tmp:
        proc = subprocess.run(
            ["hg", "archive", "-r", node, "-I", include, tmp],
            cwd=repo,
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            msg = f"hg archive failed for {entry.ver} ({node[:12]}): {proc.stderr.strip()}"
            raise CheckoutError(msg)
        exported = Path(tmp) / exported_subtree
        if not exported.is_dir():
            msg = (
                f"revision {node[:12]} ({entry.ver}) has no "
                f"{exported_subtree.as_posix()} tree -- nothing to place"
            )
            raise CheckoutError(msg)
        target = src_root / entry.ver
        if target.exists():
            shutil.rmtree(target)
        shutil.move(str(exported), str(target))
    return target


def split_frontmatter(text: str) -> tuple[str, str]:
    """Split into (frontmatter-with-delimiters, body); ("", text) if none.

    A leading ``---`` without a closing ``---`` line is NOT frontmatter
    (e.g. a stray horizontal rule) -- everything stays in the body.
    """
    if not text.startswith("---\n"):
        return "", text
    end = text.find("\n---", 4)
    if end == -1:
        return "", text
    close_end = text.find("\n", end + 1)
    if close_end == -1:
        return text, ""
    return text[: close_end + 1], text[close_end + 1 :]


def frontmatter_with_search_exclude(frontmatter: str) -> str:
    """A frontmatter block (with delimiters) carrying the search key.

    The key is inserted right after the opening delimiter -- unless a
    ``search:`` key is already there (left alone; sunsetting trees come
    from backports that carry our conventions).
    """
    if SEARCH_KEY_RE.search(frontmatter):
        return frontmatter
    return frontmatter.replace("---\n", f"---\n{SEARCH_EXCLUDE_BLOCK}", 1)


def process_sunsetting(
    tree: Path, ver: str, current_ver: str, src_root: Path
) -> int:
    """Frontmatter + banner on every page of a sunsetting snapshot.

    Order matters: frontmatter must stay the FIRST thing in the file
    (zensical only parses it there), the banner follows, then the
    untouched body. The banner links the current counterpart only when
    the page exists in the local tree -- a dead ref would break the
    build's link validation. Returns the number of processed pages.
    """
    count = 0
    for page in sorted(tree.rglob("*.md")):
        page_id = page.relative_to(tree).with_suffix("").as_posix()
        counterpart = (src_root / f"{page_id}.md").is_file()
        frontmatter, body = split_frontmatter(page.read_text())
        if frontmatter:
            frontmatter = frontmatter_with_search_exclude(frontmatter)
        else:
            frontmatter = f"---\n{SEARCH_EXCLUDE_BLOCK}---\n"
        page.write_text(
            frontmatter
            + "\n"
            + banner(page_id, ver, current_ver, counterpart)
            + body.lstrip("\n")
        )
        count += 1
    return count


def banner(page_id: str, ver: str, current_ver: str, counterpart: bool) -> str:
    """Sunsetting warning banner; links the current counterpart if it exists."""
    up = "../" * (page_id.count("/") + 1)
    if counterpart:
        target = f"{up}{page_id}"
        where = f"the [{current_ver} version]({target})"
    else:
        where = f"the [{current_ver} manual]({up}index)"
    return (
        f'!!! warning "Documentation for platform version {ver}"\n'
        f"    Platform version {ver} is in sunsetting -- this page is kept for reference.\n"
        f"    The current documentation for this topic is {where}.\n\n"
    )


def prune_orphans(src_root: Path, keep: set[str]) -> list[str]:
    """Remove undeclared ``src/<NN.NN>/`` snapshot dirs; return their names."""
    pruned = []
    if not src_root.is_dir():
        return pruned
    for child in sorted(src_root.iterdir()):
        if (
            child.is_dir()
            and re.fullmatch(r"\d{2}\.\d{2}", child.name)
            and child.name not in keep
        ):
            shutil.rmtree(child)
            pruned.append(child.name)
            log.info("orphan-pruned", ver=child.name, path=str(child))
    return pruned


def run_checkout(
    versions_path: Path, src_root: Path, repo: Path
) -> tuple[int, int, list[str]]:
    """Checkout driver: (checked-out, skipped, pruned) counts.

    Shared by ``main`` and tests -- everything except argparse and log
    configuration lives here.
    """
    versions = load_versions(versions_path)
    entries = [e for e in versions.entries() if e.status != "current"]

    manifest_path = src_root / MANIFEST_NAME
    manifest = load_manifest(manifest_path)
    fingerprint = tool_fingerprint()
    recorded: dict = manifest.get("versions", {})
    same_tool = manifest.get("tool_sha256") == fingerprint

    result = {"tool_sha256": fingerprint, "versions": {}}
    checked = skipped = 0

    for entry in entries:
        node = resolve_node(repo, entry.rev)
        if same_tool and recorded.get(entry.ver, {}).get("node") == node:
            log.info("checkout-skipped", ver=entry.ver, node=node[:12])
            skipped += 1
            result["versions"][entry.ver] = {"node": node}
            continue
        tree = checkout_version(repo, src_root, entry, node)
        log.info(
            "checkout-placed", ver=entry.ver, node=node[:12], path=str(tree)
        )
        if entry.status == "sunsetting":
            pages = process_sunsetting(
                tree, entry.ver, versions.current.ver, src_root
            )
            log.info("sunsetting-processed", ver=entry.ver, pages=pages)
        result["versions"][entry.ver] = {"node": node}
        checked += 1

    pruned = prune_orphans(src_root, set(result["versions"]))
    write_manifest(manifest_path, result)
    return checked, skipped, pruned


# Minimum log level for the CLI (matches logging.INFO; the int literal keeps
# the tool free of an ``import logging`` per the project's structlog-only rule).
_INFO_LEVEL = 20


def _configure_logging() -> None:
    """Render human-readable diagnostics to stderr (see gen_platform_versions)."""
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
    """CLI entry: ``python -m tools.checkout_versioned_docs``.

    Exit codes: ``0`` (placed/skipped/pruned), ``1`` (rev resolution or
    archive failure), ``2`` (invalid platform-versions.toml).
    """
    _configure_logging()
    parser = argparse.ArgumentParser(
        prog="checkout_versioned_docs",
        description="Place src/<ver>/ snapshots from local hg revisions (prerelease + sunsetting).",
    )
    parser.add_argument(
        "--versions", type=Path, default=DOC_ROOT / "platform-versions.toml"
    )
    parser.add_argument("--src", type=Path, default=DOC_ROOT / "src")
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    args = parser.parse_args(argv)

    try:
        checked, skipped, pruned = run_checkout(
            args.versions, args.src, args.repo
        )
    except ValueError as exc:
        log.error("versions-invalid", path=str(args.versions), error=str(exc))
        return 2
    except CheckoutError as exc:
        log.error("checkout-failed", error=str(exc))
        return 1

    log.info("checkout-done", checked=checked, skipped=skipped, pruned=pruned)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
