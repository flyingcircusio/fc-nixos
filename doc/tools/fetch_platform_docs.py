"""Merge per-version fc-nixos role documentation into one Zensical build.

This is the pure transformation layer behind ``make fetch``. It reads
``platform-versions.yaml`` and, for each declared version, bakes the
``{{ version }}`` / ``{{ release }}`` substitution tokens, rewrites stale
standalone-layout links onto the merged manual layout, adapts archived copies
(search-exclude frontmatter + sunsetting banner), and converts each version
tree from MyST to Python-Markdown (via ``tools.myst_convert``, labels
resolving within the version). EVERY version -- the stable one and each
archived release alike -- lands flat under ``src/platform-releases/<rev>``
(the declared git branch name): general docs AND role docs together, no
split. ``src/platform/`` is a HUMAN-maintained tree the fetch never touches.

The SHORT ver (``26.05``) stays the user-facing vocabulary everywhere --
``{{ version }}`` substitutions, sidebar labels, banner text -- while the
branch-name URLs make every served path unambiguous about which production
generation it documents.

Alongside the merged trees, every fetch emits ``src/_static/platform-versions.js``
-- the single data input of the client-side version switcher (a plain
``window.PLATFORM_VERSIONS = {...}`` assignment). It is a generated artifact
(kept out of the VCS via ``.hgignore``) rebuilt from the placed trees on every
run, even when all versions were skipped as unchanged.

The source tree is cloned from the public GitHub mirror
``https://github.com/flyingcircusio/fc-nixos``; a single persistent local cache
repo (``.fetch-cache/fc-nixos``) is maintained via ``--filter=blob:none
--no-checkout`` clones. For each production branch, ``git archive`` extracts
the ``doc/src`` documentation tree directly from the cache, avoiding
per-version shallow clones.
A JSON manifest under ``src/platform-releases/.fetch-manifest.json`` tracks,
per fetched version, the branch tip SHA (keyed by git branch name, under
``targets``) plus a fingerprint of the converter sources (``converter``:
sha256 over ``tools/myst_convert.py`` + ``tools/fetch_platform_docs.py``).
A version is skipped only when its SHA AND the fingerprint match, so a
converter change re-places every tree instead of leaving output converted
by the previous converter generation.
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

import certifi
import structlog
from ruamel.yaml import YAML

from tools.myst_convert import collect_label_map, convert_myst

log = structlog.get_logger()

# Files from the upstream platform repo dropped during placement -- the merged
# build is driven solely by the root src/conf.py, so the upstream's standalone
# conf.py and old master.md entry point have no place in the output tree.
_SKIP_FILES: frozenset[str] = frozenset({"master.md", "conf.py"})

# MyST substitution tokens baked at fetch time (double braces). The single-brace
# directive syntax (e.g. ``{toctree}``) is intentionally left untouched.
_VERSION_TOKEN = re.compile(r"{{\s*version\s*}}")
_RELEASE_TOKEN = re.compile(r"{{\s*release\s*}}")

# Stale standalone-layout links baked into the fc-nixos sources. The old docs
# were served at ``/platform/...``; in the merged manual those targets live at
# docs_dir-relative paths. Each known target is rewritten to a plain relative
# Markdown link resolved from the containing file (see :func:`rewrite_xrefs`);
# the anchor (when present) survives as a fragment -- after conversion the
# target heading carries that id (attr_list) or the toc slugifies to it.
# Target pages are verified to exist in the manual.
_XREF_LINK_MAP: dict[str, tuple[str, str | None]] = {
    "/platform/index.html": ("support/index.md", "support"),
    "/platform/infrastructure/networking/networking.html": (
        "infrastructure/networking/networking.md",
        "logical-networks",
    ),
    "platform/infrastructure/networking/networking.html": (
        "infrastructure/networking/networking.md",
        None,
    ),
    "/platform/reference/users/index.html": ("platform/users/index.md", None),
    "/platform/changes": ("changes/index.md", None),
}

# Malformed link whose display text is the full URL but whose target is a bare
# hostname: ``[<url>](search.flyingcircus.io)`` -> ``[<url>](<url>)``.
_BARE_HOST_LINK = re.compile(r"\[([^]]+)\]\(search\.flyingcircus\.io\)")

# Any Markdown link ``[text](target)``; the replacement only fires for targets
# in the xref maps above, so external links pass through untouched.
_MD_LINK = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

# Public fc-nixos mirror the fetch clones from. Overridable via FC_NIXOS_REMOTE
# (e.g. a local mirror or a CI cache).
_FC_NIXOS_REMOTE = "https://github.com/flyingcircusio/fc-nixos"

# Persistent cache directory for the local repo clone (relative to project root).
_FETCH_CACHE_DIR = ".fetch-cache"

# Manifest filename stored under the output platform dir.
_MANIFEST_FILENAME = ".fetch-manifest.json"

# Converter sources covered by the manifest fingerprint: editing any of them
# invalidates every converted platform tree.
_CONVERTER_SOURCES = ("myst_convert.py", "fetch_platform_docs.py")


def converter_fingerprint() -> str:
    """SHA-256 over the converter sources (``tools/`` module files).

    The fingerprint is stored in the fetch manifest next to the per-target
    SHAs; ``run_fetch`` skips a version only when its branch SHA AND the
    fingerprint match, so a converter change re-places every tree whose SHA
    alone did not change. Reading the sources from this module's own
    directory keeps the fingerprint stable regardless of the working
    directory the fetch runs from.
    """
    tools_dir = Path(__file__).resolve().parent
    digest = hashlib.sha256()
    for name in _CONVERTER_SOURCES:
        digest.update((tools_dir / name).read_bytes())
    return digest.hexdigest()


@dataclass(slots=True)
class VersionRef:
    """One archived platform version and its git production branch.

    ``sunsetting`` controls whether the sidebar nav marks this version as
    sunsetting (``Platform <ver> (sunsetting)``). It defaults to ``True`` so an
    archived version is flagged unless the config explicitly opts out with
    ``sunset: false`` -- a still-supported older release should not be
    advertised as sunsetting. The constructor accepts the YAML key ``sunset``
    (matching ``platform-versions.yaml``); the attribute is ``sunsetting``.
    """

    ver: str
    rev: str
    sunsetting: bool = True

    def __init__(self, ver: str, rev: str, sunset: bool | None = None) -> None:
        self.ver = ver
        self.rev = rev
        self.sunsetting = sunset if sunset is not None else True


@dataclass(slots=True)
class PlatformConfig:
    """The version set the single-build pipeline merges into one tree."""

    stable: str
    archived: list[VersionRef]


def load_config(path: Path) -> PlatformConfig:
    """Parse ``platform-versions.yaml`` into the stable version + ordered archived refs.

    ``stable`` is the manual's primary platform version (placed flat under
    ``platform-releases/fc-<ver>-production/`` with all its role docs); each
    ``archived`` entry carries its own git production branch (``rev``) so the
    fetch boundary can check it out independently. An optional ``sunset``
    flag (default ``True``) marks the version as sunsetting in the sidebar
    nav.
    """
    yaml = YAML(typ="safe")
    with path.open(encoding="utf-8") as fh:
        data = yaml.load(fh)
    config = PlatformConfig(
        stable=data["stable"],
        archived=[
            VersionRef(
                ver=item["ver"],
                rev=item["rev"],
                sunset=item.get("sunset", True),
            )
            for item in data["archived"]
        ],
    )
    sunset_versions = [e.ver for e in config.archived if e.sunsetting]
    log.debug(
        "platform-config-loaded",
        path=str(path),
        stable=config.stable,
        archived_count=len(config.archived),
        sunset_versions=sunset_versions,
    )
    return config


# Markers delimiting the generated platform-versions nav inside ``zensical.toml``
# (the Zensical equivalent of the old toctree block in ``src/index.md``).
# ``make fetch`` rewrites everything between them from ``platform-versions.yaml``
# plus the placed trees, so the sidebar nav stays in sync with the config.
_PLATFORM_NAV_BEGIN = "# BEGIN platform-versions"
_PLATFORM_NAV_END = "# END platform-versions"

# The zensical config files the generated nav blocks are kept in sync with:
# the English build (``zensical.toml``) and the German translation build
# (``zensical-de.toml``). Both builds share the same docs_dir-relative page
# paths (``src-de/`` is a derived copy of ``src/``), so every generator
# writes the SAME block into both -- one source of truth, two builds.
CONFIG_TOMLS = ("zensical.toml", "zensical-de.toml")


def _nav_pages(trees: Sequence[Path], output_root: Path) -> list[str]:
    """Sorted docs_dir-relative ``.md`` paths for one version's placed trees.

    The version index (``<prefix>index.md``) comes first so it is the section's
    landing page; everything else follows alphabetically. Every version spans
    exactly ONE flat tree (``platform-releases/<rev>/``). A missing tree
    yields no pages.
    """
    pages = sorted(
        md.relative_to(output_root).as_posix()
        for tree in trees
        for md in tree.rglob("*.md")
    )
    index = [p for p in pages if p.endswith("index.md")]
    rest = [p for p in pages if not p.endswith("index.md")]
    return index + rest


def render_platform_nav(config: PlatformConfig, output_root: Path) -> str:
    """Render the marked platform-versions nav block for ``zensical.toml``.

    ONE wrapper group -- "Platform Releases (Versioned Docs)" -- holding
    every platform version: stable first, then each archived version in
    config order, labelled with the wip-style "Platform " prefix plus the
    lifecycle suffix (``(stable)`` / ``(sunsetting)``). The versions nest
    under a captioned group instead of being top-level siblings, so paired
    with the ``navigation.sections`` theme feature the wrapper renders as a
    static sidebar section whose nested version groups fold along the
    active path (the wip/furo look, see 1947:bfb6acb20ece). Each version
    entry lists its pages (index first, then alphabetical) -- the Zensical
    equivalent of the old toctree-driven sidebar. Entries carry a trailing
    comma: TOML arrays accept one after the last element, so the same
    block is valid at the end of the nav array and followed by
    hand-curated entries.
    """

    def version_entry(label: str, pages: Sequence[str]) -> str:
        return (
            f'    {{ "{label}" = [\n'
            + ",\n".join(f'        "{p}"' for p in pages)
            + "\n    ] },"
        )

    stable_rev = stable_branch(config.stable)
    versions: list[str] = []
    stable_trees = (output_root / "platform-releases" / stable_rev,)
    stable = _nav_pages(stable_trees, output_root)
    versions.append(version_entry(f"Platform {config.stable} (stable)", stable))
    for ref in config.archived:
        label = "Platform " + ref.ver + (" (sunsetting)" if ref.sunsetting else "")
        pages = _nav_pages((output_root / "platform-releases" / ref.rev,), output_root)
        versions.append(version_entry(label, pages))
    wrapper = (
        '  { "Platform Releases (Versioned Docs)" = [\n'
        + "\n".join(versions)
        + "\n  ] },"
    )
    # No trailing newline: the marker regex matches exactly BEGIN..END
    # without the newline after END -- a trailing \n here would add one
    # blank line per fetch run (non-idempotent).
    return f"{_PLATFORM_NAV_BEGIN}\n" + wrapper + f"\n{_PLATFORM_NAV_END}"


def update_platform_nav(
    toml_text: str, config: PlatformConfig, output_root: Path
) -> str:
    """Replace the marked platform-versions nav block in a zensical config.

    If the markers are absent but a ``nav = [...]`` array exists, the block is
    inserted right after the opening bracket so generated entries join the
    hand-curated ones. If neither markers nor a nav array exist, the text is
    returned unchanged with a loud log event -- the tool cannot invent the
    build structure on its own.
    """
    block = render_platform_nav(config, output_root)
    pattern = re.compile(
        re.escape(_PLATFORM_NAV_BEGIN) + r".*?" + re.escape(_PLATFORM_NAV_END),
        re.DOTALL,
    )
    if pattern.search(toml_text):
        return pattern.sub(block, toml_text)
    nav_match = re.search(r"^nav\s*=\s*\[", toml_text, re.MULTILINE)
    if nav_match:
        return (
            toml_text[: nav_match.end()] + "\n" + block + toml_text[nav_match.end() :]
        )
    log.warning(
        "platform-nav-insert-skipped",
        reason="no nav array found in the config",
    )
    return toml_text


# Output location of the version switcher's data file, relative to the fetch
# output root. Referenced by the committed switcher assets in src/_static.
_SWITCHER_DATA_REL = Path("_static") / "platform-versions.js"


def _page_inventory(tree: Path, prefix: str) -> dict[str, str]:
    """Map every Markdown page under *tree* to the URL *prefix* it lives at.

    A page id is the tree-relative path without the ``.md`` suffix (posix
    slashes), so nested general docs (``infrastructure/networking``) keep a
    unique id and the dir-form switch target ``<prefix><id>/`` resolves. Non-
    Markdown files (images, ...) are not pages. A missing *tree* yields an
    empty inventory (a version whose placement was skipped leaves the
    previously placed tree in place -- and an absent tree simply contributes
    no pages).
    """
    if not tree.is_dir():
        return {}
    return {
        md.relative_to(tree).with_suffix("").as_posix(): prefix
        for md in sorted(tree.rglob("*.md"))
    }


def _version_entry(
    ver: str, rev: str, status: str, trees: Sequence[tuple[Path, str]]
) -> dict:
    """Build one ``versions[]`` entry for *ver* from its placed doc trees.

    *trees* pairs each on-disk source directory with the URL prefix its pages
    live at (every version spans exactly ONE flat tree under
    ``platform-releases/<rev>/``). Every version MUST provide an ``index``
    page -- it is the flyout's fallback target -- so a tree without one
    crashes the fetch loudly (a ``platform-versions-js-index-missing``
    exception event carrying the scanned trees, then ``RuntimeError``)
    instead of shipping a broken switcher. Dir-form:
    the ``index`` page-id is dropped from the shipped ``pages`` inventory
    (zensical serves directory URLs -- a switch target for page ``<id>`` is
    ``<prefix><id>/``) and the version's ``index`` is the DIRECTORY URL of
    its index page; index pages are located by the switcher's URL-grammar
    fallback instead.

    ``ver`` stays the release number for labels and ``{{ version }}``
    substitutions; ``rev`` carries the full git branch name -- the URL
    vocabulary the prefixes and the switcher's fallback are built from.
    """
    pages: dict[str, str] = {}
    for tree, prefix in trees:
        pages.update(_page_inventory(tree, prefix))
    index_dir = pages.pop("index", None)
    if index_dir is None:
        scanned = ", ".join(str(t) for t, _ in trees)
        log.exception(
            "platform-versions-js-index-missing",
            version=ver,
            scanned_trees=scanned,
        )
        raise RuntimeError(
            f"version {ver!r} has no index page under {scanned} -- "
            "cannot emit platform-versions.js (broken placement?)"
        )
    return {
        "ver": ver,
        "rev": rev,
        "status": status,
        "label": f"{ver} ({status})",
        "index": index_dir,
        "pages": pages,
    }


def write_platform_versions_js(output_root: Path, config: PlatformConfig) -> Path:
    """Emit ``<output_root>/_static/platform-versions.js`` for the switcher.

    Writes the single data input of the client-side version switcher: a plain
    ``window.PLATFORM_VERSIONS = <JSON>;`` assignment (parseable without a JS
    engine) whose shape is pinned by ``tests/platform_versions_shape.py`` and
    shared with the frontend e2e tests. Page inventories are derived from the
    PLACED trees, so the file always mirrors what ``make fetch`` actually
    wrote -- also on runs where every version was skipped as unchanged.

    Version vocabulary: ``stable`` for the primary version, ``sunsetting``
    for archived ones (the default); an archived entry with ``sunset: false``
    is still supported and labelled ``supported``. Every entry carries the
    full branch name as ``rev`` (the URL vocabulary: branch-named prefixes
    and the switcher's fallback derive from it) while ``ver`` stays the
    release number used for labels.
    """
    stable_rev = stable_branch(config.stable)
    entries = [
        _version_entry(
            config.stable,
            stable_rev,
            "stable",
            (
                (
                    output_root / "platform-releases" / stable_rev,
                    f"platform-releases/{stable_rev}/",
                ),
            ),
        )
    ]
    for ref in config.archived:
        status = "sunsetting" if ref.sunsetting else "supported"
        entries.append(
            _version_entry(
                ref.ver,
                ref.rev,
                status,
                (
                    (
                        output_root / "platform-releases" / ref.rev,
                        f"platform-releases/{ref.rev}/",
                    ),
                ),
            )
        )
    payload = {"current": config.stable, "versions": entries}

    js_path = output_root / _SWITCHER_DATA_REL
    js_path.parent.mkdir(parents=True, exist_ok=True)
    js_path.write_text(
        f"window.PLATFORM_VERSIONS = {json.dumps(payload, indent=2)};\n",
        encoding="utf-8",
    )
    log.info(
        "platform-versions-js-emitted",
        path=str(js_path),
        current=config.stable,
        versions=[e["ver"] for e in entries],
        pages_per_version=[len(e["pages"]) for e in entries],
    )
    return js_path


def bake_substitutions(text: str, version: str, release: str) -> str:
    """Replace ``{{ version }}`` / ``{{ release }}`` tokens with literals.

    Only the double-brace MyST substitution tokens are rewritten; single-brace
    directive syntax like ``{toctree}`` survives untouched.
    """
    text = _VERSION_TOKEN.sub(version, text)
    text = _RELEASE_TOKEN.sub(release, text)
    return text


def rewrite_xrefs(text: str, *, file_rel: str) -> str:
    """Rewrite stale standalone-layout links onto the merged manual layout.

    Each known ``/platform/...`` target becomes a plain relative Markdown link
    resolved from *file_rel* (the FINAL tree-relative path of the containing
    file, so the climb is correct for nested pages). This replaces the old
    ``{ref}``/``{doc}`` rewriting: Python-Markdown has no global label registry,
    so stale absolute ``.html`` targets must become concrete relative links at
    fetch time. Also repairs the malformed ``[<url>](search.flyingcircus.io)``
    link pattern. External links pass through untouched.
    """

    def link_repl(m: re.Match) -> str:
        text_part, target = m.group(1), m.group(2)
        # Match on the path only -- an explicit fragment (#anchor) in the link
        # wins over the map's default anchor; without one, the map anchor is
        # used (the stale target's canonical heading).
        path_part, _, fragment = target.partition("#")
        if path_part in _XREF_LINK_MAP:
            page, anchor = _XREF_LINK_MAP[path_part]
            url = _relative_md_link(file_rel, page, fragment or anchor)
            return f"[{text_part}]({url})"
        return m.group(0)

    text = _MD_LINK.sub(link_repl, text)
    return _BARE_HOST_LINK.sub(lambda m: f"[{m.group(1)}]({m.group(1)})", text)


def _relative_md_link(from_file: str, target_rel: str, anchor: str | None) -> str:
    """Relative Markdown link URL from *from_file* to *target_rel*.

    Pure-posix, deterministic, keeps the ``.md`` suffix -- Zensical rewrites
    ``.md`` links to ``.html`` (directory URLs) at build time. *anchor* is
    appended as a fragment when present.
    """
    src_dir = PurePosixPath(from_file).parent
    rel = PurePosixPath(target_rel)
    if src_dir == PurePosixPath("."):
        url = str(rel)
    else:
        depth = len(src_dir.parts)
        url = "/".join([".."] * depth + [str(rel)])
    if anchor:
        url += f"#{anchor}"
    return url


def target_dir(branch: str) -> str:
    """Return the manifest target name for a platform version's git branch.

    The manifest key IS the full branch name (e.g. ``fc-26.05-production``).
    Using the branch name directly -- rather than reconstructing it from a
    version string -- keeps the mapping robust against future branch suffixes
    (``-staging``, ``-unstable``, ...) without code changes.
    """
    return branch


def stable_branch(ver: str) -> str:
    """The git production branch name of the stable version.

    DERIVED from the declared stable ver (``26.05`` -> ``fc-26.05-production``)
    -- ``platform-versions.yaml`` gains no separate field for it. The branch
    name doubles as the stable tree's directory name under
    ``platform-releases/`` and as the ``rev`` field of the switcher payload's
    stable entry.
    """
    return f"fc-{ver}-production"


def _version_target(output_root: Path, rev: str) -> Path:
    """The output directory a version's docs are placed into.

    EVERY version -- stable and archived alike -- lives flat at
    ``<output_root>/platform-releases/<rev>/`` (the full git branch name),
    so a served URL always names the production generation it documents.
    ``src/platform/`` is a human tree the fetch never touches.
    """
    return output_root / "platform-releases" / rev


def _target_has_content(tgt_path: Path) -> bool:
    """True when a previously fetched version is present on disk."""
    return tgt_path.is_dir() and any(p.is_file() for p in tgt_path.rglob("*"))


def place_version(
    src_root: Path,
    version: str,
    release: str,
    branch: str,
    is_stable: bool,
    output_root: Path,
    *,
    stable_rev: str | None = None,
) -> Path:
    """Bake + rewrite + convert one version's docs into the merged tree.

    Every Markdown file under ``src_root`` is rewritten (substitutions baked,
    stale-layout links rewritten to plain relative Markdown links, archived
    copies get the sunsetting banner prepended) into the target directory and
    then converted from MyST to Python-Markdown with a tree-local label map;
    non-Markdown assets are copied verbatim so role images survive. Files
    named in :data:`_SKIP_FILES` (the old ``master.md`` entry point and the
    upstream standalone ``conf.py``) are dropped -- the merged build is
    driven solely by the root ``zensical.toml``.

    EVERY version -- stable (``is_stable=True``) and archived alike -- lands
    flat under ``<output_root>/platform-releases/<branch>/``: general docs
    AND role docs together in one tree, no split, no reference rewriting.
    Archived versions additionally carry the sunsetting banner on every page;
    its same-page link resolves against the stable tree named by
    *stable_rev* (``run_fetch`` places the stable version first and passes
    its branch down).

    Placement clears ONLY the version's own target directory -- sibling
    version dirs, the fetch manifest file, human content under ``platform/``
    and anything else under the output root are never touched.

    Returns the destination directory (``platform-releases/<branch>/``).
    """
    dest = _version_target(output_root, branch)
    if dest.exists():
        log.info("place-version-clearing-dest", dest=str(dest))
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)

    log.info(
        "place-version-started",
        version=version,
        release=release,
        is_stable=is_stable,
        dest=str(dest),
        src_root=str(src_root),
    )
    placed = 0
    skipped = 0
    for src_file in sorted(src_root.rglob("*")):
        if not src_file.is_file():
            continue
        rel = src_file.relative_to(src_root)
        if rel.name in _SKIP_FILES:
            skipped += 1
            log.debug("place-version-skipped", rel=str(rel), reason="legacy-entry-doc")
            continue
        out_file = dest / rel
        out_file.parent.mkdir(parents=True, exist_ok=True)
        if src_file.suffix == ".md":
            final_rel = out_file.relative_to(output_root).as_posix()
            rendered = rewrite_xrefs(
                bake_substitutions(
                    src_file.read_text(encoding="utf-8"), version, release
                ),
                file_rel=final_rel,
            )
            if not is_stable:
                rendered = _adapt_archived_page(
                    rendered, final_rel, output_root, stable_rev
                )
            out_file.write_text(rendered, encoding="utf-8")
        else:
            shutil.copyfile(src_file, out_file)
        placed += 1
        log.debug(
            "place-version-wrote", rel=str(rel), is_markdown=src_file.suffix == ".md"
        )
    converted = convert_version_tree(output_root, [dest])
    log.info(
        "place-version-finished",
        version=version,
        dest=str(dest),
        placed=placed,
        skipped=skipped,
        converted=converted,
    )
    return dest


_SEARCH_EXCLUDE_FRONTMATTER = "---\nsearch:\n  exclude: true\n---\n\n"
"""Frontmatter keeping the archived copies out of the site search index."""


def _archived_counterpart(
    file_rel: str, output_root: Path, stable_rev: str | None
) -> str | None:
    """Docs_dir-relative stable counterpart for an archived page, or None.

    Every version lands flat under ``platform-releases/<rev>/``, so the
    same-page counterpart of an archived page is simply the file at the same
    tree-relative path inside the stable version's own tree. Without a known
    stable branch -- or when the page only exists in the archived release --
    there is no counterpart and the caller falls back.
    """
    rel = PurePosixPath(file_rel)
    parts = rel.parts
    if len(parts) < 3 or parts[0] != "platform-releases" or stable_rev is None:
        return None
    version_rel = PurePosixPath(*parts[2:])
    prefix = f"platform-releases/{stable_rev}"
    if (output_root / prefix / version_rel).is_file():
        return f"{prefix}/{version_rel}"
    return None


def _adapt_archived_page(
    text: str, file_rel: str, output_root: Path, stable_rev: str | None = None
) -> str:
    """Adapt an archived platform page: search-excluded + sunsetting banner.

    Replaces the Sphinx ``_ext_archived_banner`` doctree hook: every archived
    platform page carries ``search: exclude: true`` frontmatter (the sunsetting
    copies stay out of the site search index -- the stable docs are the ones
    worth finding) and opens with a ``!!! warning`` banner. The banner links to
    the SAME page in the current (stable) version -- mirroring the version
    switcher's same-page semantics -- falling back to the stable index when
    the page is archived-only, or to the manual root when the stable tree was
    not placed (``run_fetch`` places it first and passes its branch down).
    English-only -- the platform pages are not translated.
    """
    target = _archived_counterpart(file_rel, output_root, stable_rev)
    if target is None:
        stable_index = (
            output_root / "platform-releases" / str(stable_rev) / "index.md"
            if stable_rev
            else None
        )
        if stable_index is not None and stable_index.is_file():
            target = f"platform-releases/{stable_rev}/index.md"
        else:
            target = "index.md"
    link = _relative_md_link(file_rel, target, None)
    banner = (
        "!!! warning\n"
        "    This is a sunsetting version of the platform documentation. "
        f"Go to [the current version]({link}) for optimized support.\n\n"
    )
    return _SEARCH_EXCLUDE_FRONTMATTER + banner + text


def convert_version_tree(output_root: Path, trees: Sequence[Path]) -> int:
    """Pass-2 conversion: MyST -> Python-Markdown across one version's trees.

    Uses the myst_convert library API directly (``collect_label_map`` +
    ``convert_myst``): the label map spans the version's whole tree, so
    references resolve within the version only and archived copies never
    collide with stable ones. Runs on the FINAL merged-tree paths -- the
    conversion runs after placement so the label map keys and relative
    targets are the real build paths.

    Returns the number of files that actually changed.
    """
    contents: dict[str, str] = {}
    for tree in trees:
        for md in sorted(tree.rglob("*.md")):
            rel = md.relative_to(output_root).as_posix()
            contents[rel] = md.read_text(encoding="utf-8")
    labels = collect_label_map(contents)
    converted = 0
    for rel, text in contents.items():
        new_text = convert_myst(text, file_rel=rel, labels=labels)
        if new_text != text:
            (output_root / rel).write_text(new_text, encoding="utf-8")
            converted += 1
    log.info(
        "version-tree-converted",
        trees=[str(t) for t in trees],
        files=len(contents),
        converted=converted,
    )
    return converted


def _git_env() -> dict[str, str]:
    """Environment for git subprocesses: point TLS at certifi's CA bundle.

    The build environment has no system CA store (Nix profile), so git's default
    verification fails with ``unable to get local issuer certificate``. certifi
    is a hard dependency (``pyproject.toml``) that ships a bundle in the venv --
    use it directly. A pre-existing ``GIT_SSL_CAINFO`` (e.g.
    on a machine with a working CA store) is never overridden.
    """
    env = dict(os.environ)
    env.setdefault("GIT_SSL_CAINFO", certifi.where())
    return env


def run_command(
    cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess:
    """Run *cmd* in *cwd* (with optional *env*), logging the invocation first.

    On non-zero exit, surface the COMPLETE stdout/stderr (structured log AND
    embedded in the raised error) instead of swallowing it via capture_output.
    """
    log.info("run-command", cmd=cmd, cwd=str(cwd))
    result = subprocess.run(
        cmd, cwd=str(cwd), capture_output=True, text=True, env=env, check=False
    )
    if result.returncode != 0:
        log.exception(
            "command-failed",
            cmd=cmd,
            cwd=str(cwd),
            returncode=result.returncode,
            stdout=result.stdout,
            stderr=result.stderr,
        )
        raise RuntimeError(
            f"command failed (exit {result.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{result.stdout}"
            f"--- stderr ---\n{result.stderr}"
        )
    return result


def ensure_repo(cache_dir: Path, remote: str, *, run_fn=run_command) -> Path:
    """Ensure a persistent local clone of *remote* exists under *cache_dir*.

    On the first run, clones with ``--filter=blob:none --no-checkout`` so no
    working tree is created. On subsequent runs, runs ``git fetch --prune``
    to pick up new branches and remove deleted ones. Returns the repo path.
    """
    repo_path = cache_dir / "fc-nixos"
    repo_log = log.bind(repo=str(repo_path))
    if not repo_path.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        repo_log.info(
            "repo-clone-started",
            remote=remote,
            cache=str(cache_dir),
        )
        run_fn(
            [
                "git",
                "clone",
                "--filter=blob:none",
                "--no-checkout",
                remote,
                # Absolute target: git resolves a relative target against ITS
                # OWN cwd (the cache dir), while subprocess.run resolves cwd
                # against the process cwd. With a relative ``cache_dir`` (as
                # production uses: ``.fetch-cache``) that double resolution
                # landed the repo at ``<cache>/<cache>/fc-nixos``. An absolute
                # target is unambiguous regardless of cwd.
                str(repo_path.resolve()),
            ],
            cwd=cache_dir,
            env=_git_env(),
        )
        repo_log.info("repo-clone-finished")
    else:
        repo_log.info("repo-fetch-started")
        run_fn(
            ["git", "fetch", "--prune"],
            cwd=repo_path,
            env=_git_env(),
        )
        repo_log.info("repo-fetch-finished")
    return repo_path


def resolve_tips(
    repo_path: Path, branches: Sequence[str], *, run_fn=run_command
) -> dict[str, str]:
    """Resolve the tip SHA of each branch in the local repo.

    Returns a dict mapping branch name to its HEAD commit SHA. All branches are
    fetched (via ``ensure_repo``) before resolution, so new production branches
    are available immediately.

    The branches are resolved as fully-qualified remote-tracking refs
    (``refs/remotes/origin/<branch>``): a default clone stores every remote
    branch under ``refs/remotes/origin/``, and a bare short name does NOT
    resolve to that location (gitrevisions(7) only checks ``refs/heads/``,
    ``refs/tags/`` and ``refs/remotes/<name>`` where ``<name>`` is the whole
    literal). ``origin`` is the remote name a plain ``git clone`` always uses.
    """
    tips: dict[str, str] = {}
    for branch in branches:
        result = run_fn(
            ["git", "rev-parse", f"refs/remotes/origin/{branch}"],
            cwd=repo_path,
            env=_git_env(),
        )
        tips[branch] = result.stdout.strip()
    log.debug("tips-resolved", branches=list(tips.keys()))
    return tips


def archive_from_repo(
    repo_path: Path, sha: str, dest: Path, *, run_fn=run_command
) -> None:
    """Extract the ``doc/src`` documentation tree from *repo_path* at *sha* into *dest*.

    fc-nixos keeps the actual role sources under ``doc/src/``; the ``doc``
    directory itself only holds Nix build files (``default.nix``,
    ``myst-docutils.nix``). Extracting ``doc/src`` -- not ``doc`` -- ensures
    role pages land at ``dest/index.md`` rather than ``dest/src/index.md``: the
    former is the path the manual's root toctree references, the latter would
    leave the platform sidebar empty (``toc.not_readable``).

    Pipes ``git archive sha doc/src`` into ``tar -x -C dest``; the archive
    prefixes entries with ``doc/src/``, so the prefix is stripped (contents
    moved up two levels) after extraction. The *dest* directory is created if
    it does not exist. A failing pipeline side logs a structured
    ``git-archive-failed`` / ``tar-extract-failed`` exception event (exit
    code + stderr) before the ``RuntimeError`` raises.
    """
    dest.mkdir(parents=True, exist_ok=True)
    log.info(
        "archive-from-repo-started",
        repo=str(repo_path),
        sha=sha,
        dest=str(dest),
    )
    tar_proc = subprocess.Popen(
        ["tar", "-x", "-C", str(dest)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    archive_proc = subprocess.Popen(
        ["git", "-C", str(repo_path), "archive", sha, "doc/src"],
        stdout=tar_proc.stdin,
        stderr=subprocess.PIPE,
        env=_git_env(),
    )
    tar_proc.communicate()
    archive_proc.communicate()

    if archive_proc.returncode != 0:
        stderr_text = (
            archive_proc.stderr.read().decode(errors="replace")
            if archive_proc.stderr
            else ""
        )
        log.exception(
            "git-archive-failed",
            repo=str(repo_path),
            sha=sha,
            dest=str(dest),
            returncode=archive_proc.returncode,
            stderr=stderr_text,
        )
        raise RuntimeError(
            f"git archive failed (exit {archive_proc.returncode}): {stderr_text}"
        )
    if tar_proc.returncode != 0:
        stderr_text = (
            tar_proc.stderr.read().decode(errors="replace") if tar_proc.stderr else ""
        )
        log.exception(
            "tar-extract-failed",
            dest=str(dest),
            returncode=tar_proc.returncode,
            stderr=stderr_text,
        )
        raise RuntimeError(
            f"tar extract failed (exit {tar_proc.returncode}): {stderr_text}"
        )

    # git archive prefixes entries with "doc/src/"; move the src contents up
    # two levels so role pages sit at dest/ (not dest/src/), then drop the
    # now-empty doc/ wrapper.
    src_prefix = dest / "doc" / "src"
    if src_prefix.is_dir():
        for entry in src_prefix.iterdir():
            shutil.move(str(entry), str(dest / entry.name))
        src_prefix.rmdir()
        (dest / "doc").rmdir()

    log.info("archive-from-repo-finished", sha=sha, dest=str(dest))


def load_manifest(output: Path) -> dict[str, Any]:
    """Load the fetch manifest: converter fingerprint + per-target SHAs.

    Returns ``{"converter": <fingerprint or None>, "targets": {branch: sha}}``.
    A missing file is a cache miss (``converter=None``, ``targets={}``) -- and
    so is a legacy flat ``{branch: sha}`` manifest from before the fingerprint
    existed: it cannot prove which converter generation built the trees, so
    every version is re-placed. No compatibility shim -- the legacy format is
    never written again.
    """
    manifest_path = output / "platform-releases" / _MANIFEST_FILENAME
    if not manifest_path.exists():
        return {"converter": None, "targets": {}}
    data = json.loads(manifest_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or "targets" not in data:
        log.info(
            "manifest-cache-miss",
            path=str(manifest_path),
            reason="legacy manifest without converter/targets -- full re-placement",
        )
        return {"converter": None, "targets": {}}
    log.debug(
        "manifest-loaded",
        path=str(manifest_path),
        targets=len(data["targets"]),
        converter=data.get("converter"),
    )
    return {"converter": data.get("converter"), "targets": data["targets"]}


def save_manifest(output: Path, manifest: dict[str, Any]) -> None:
    """Persist the fetch manifest under ``output/platform-releases/``."""
    releases_dir = output / "platform-releases"
    releases_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = releases_dir / _MANIFEST_FILENAME
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    log.debug(
        "manifest-saved",
        path=str(manifest_path),
        targets=len(manifest["targets"]),
        converter=manifest.get("converter"),
    )


def run_fetch(
    config_path: Path,
    output: Path,
    *,
    remote: str = _FC_NIXOS_REMOTE,
    archive_fn: Path | None = None,
) -> None:
    """Orchestrate the single-build fetch using a persistent repo cache.

    Reads ``platform-versions.yaml`` and for each declared version, compares
    the branch tip SHA and the converter fingerprint against the manifest.
    Unchanged versions (SHA matches, converter fingerprint matches and target
    dir exists) are skipped; a converter change re-places EVERY version --
    the converted trees were built by a different converter generation.
    Changed versions are extracted via ``git archive`` from the persistent
    cache repo. Orphaned target directories under ``platform-releases/``
    (dropped releases, short-ver leftovers) are pruned; ``src/platform/`` is
    a human tree the fetch never touches.

    *archive_fn* is the cache directory path override for testing; when ``None``,
    a real ``.fetch-cache`` directory is used.
    """
    cfg = load_config(config_path)
    output.mkdir(parents=True, exist_ok=True)

    if archive_fn is not None:
        cache_dir = archive_fn
    else:
        cache_dir = config_path.parent / _FETCH_CACHE_DIR

    repo_path = ensure_repo(cache_dir, remote)

    # Collect all branches we need to resolve.
    stable_rev = stable_branch(cfg.stable)
    all_branches = [stable_rev] + [e.rev for e in cfg.archived]
    tips = resolve_tips(repo_path, all_branches)

    fingerprint = converter_fingerprint()
    manifest = load_manifest(output)
    converter_matches = manifest["converter"] == fingerprint
    targets: dict[str, str] = manifest["targets"]
    manifest_path = output / "platform-releases" / _MANIFEST_FILENAME

    # Build target -> SHA mapping for the manifest keys (branch names).
    stable_sha = tips[stable_rev]
    wanted_targets: dict[str, str] = {
        target_dir(stable_rev): stable_sha,
    }
    wanted_targets.update({target_dir(e.rev): tips[e.rev] for e in cfg.archived})

    # Process each version: skip only when SHA, converter fingerprint AND
    # on-disk content all match; extract otherwise. The stable version goes
    # FIRST -- the archived banners resolve their same-page links against
    # the already-placed stable tree.
    for version, rev, is_stable in [
        (cfg.stable, stable_rev, True),
        *[(e.ver, e.rev, False) for e in cfg.archived],
    ]:
        tgt = target_dir(rev)
        sha = tips[rev]
        tgt_path = _version_target(output, rev)

        sha_matches = targets.get(tgt) == sha
        if sha_matches and converter_matches and _target_has_content(tgt_path):
            log.info(
                "version-skipped",
                version=version,
                target=tgt,
                sha=sha[:12],
                converter=fingerprint[:12],
                manifest_path=str(manifest_path),
            )
            continue

        if not sha_matches:
            extract_reason = "sha-changed"
        elif not converter_matches:
            extract_reason = "converter-changed"
        else:
            extract_reason = "target-empty"
        log.info(
            "version-extracting",
            version=version,
            target=tgt,
            sha=sha[:12],
            reason=extract_reason,
            converter=fingerprint[:12],
            manifest_path=str(manifest_path),
        )
        with tempfile.TemporaryDirectory() as tmp:
            src_root = Path(tmp)
            archive_from_repo(repo_path, sha, src_root)
            release = f"{version} ({sha[:12]})"
            place_version(
                src_root,
                version,
                release,
                rev,
                is_stable,
                output,
                stable_rev=stable_rev,
            )

        targets[tgt] = sha

    # Prune orphaned directories -- the layout is keyed by full branch names
    # under platform-releases/ (stable tree included): short-ver dirs (e.g.
    # 25.11) and dropped releases are orphans. The manifest FILE at the
    # platform-releases/ root is never pruned (only directories are), and
    # src/platform/ is a HUMAN tree the fetch never touches -- not even to
    # clean up leftovers of the old split layout.
    releases_dir = output / "platform-releases"
    if releases_dir.is_dir():
        valid_revs = {stable_rev} | {e.rev for e in cfg.archived}
        for entry in sorted(releases_dir.iterdir()):
            if entry.is_dir() and entry.name not in valid_revs:
                log.info("orphan-pruned", target=entry.name)
                shutil.rmtree(str(entry))
                targets.pop(entry.name, None)

    # Prune manifest targets no longer declared in the config.
    for key in sorted(targets):
        if key not in wanted_targets:
            targets.pop(key, None)

    save_manifest(output, {"converter": fingerprint, "targets": targets})

    # Keep the generated platform-versions nav in EVERY zensical config in
    # sync with the config + placed trees (EN and DE build from the same
    # page paths). Missing configs log a loud skip -- the tool cannot invent
    # the build structure on its own.
    for name in CONFIG_TOMLS:
        toml_path = config_path.parent / name
        if toml_path.exists():
            toml_path.write_text(
                update_platform_nav(toml_path.read_text(encoding="utf-8"), cfg, output),
                encoding="utf-8",
            )
            log.info("platform-nav-updated", toml=str(toml_path))
        else:
            log.warning(
                "platform-nav-skipped",
                reason=f"no {name} next to the config",
                toml=str(toml_path),
            )

    # Rebuild the version switcher's data file from the placed trees on EVERY
    # run (also all-skipped ones): it must always mirror the current config +
    # tree state, never a stale copy from an earlier fetch.
    switcher_data = write_platform_versions_js(output, cfg)

    log.info(
        "run-fetch-finished",
        stable=cfg.stable,
        archived_count=len(cfg.archived),
        converter=fingerprint[:12],
        output=str(output),
        switcher_data=str(switcher_data),
    )


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry: ``python -m tools.fetch_platform_docs <config> <output>``."""
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 2:
        log.warning(
            "fetch-cli-usage",
            args=args,
            usage="python -m tools.fetch_platform_docs "
            "<platform-versions.yaml> <output-dir>",
        )
        return 2
    config_path, output = Path(args[0]), Path(args[1])
    run_fetch(config_path, output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
