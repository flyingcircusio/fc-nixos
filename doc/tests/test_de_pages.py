"""Executable spec for the German pages under ``doc/src/de/**``.

The ``/de/`` tree holds translated pages that live as ordinary (unlisted)
pages of the ONE zensical build: directories mirror URLs --
``src/de/<path>.md`` is served at ``/de/<path>/``. Four properties pin
that design:

- every relative markdown ref on a German page resolves inside the
  source tree (untranslated topics link back into the English tree --
  the file-relative refs must match the ``de/`` nesting level, which
  ``invalid_links`` build validation only covers at build time and
  historically was silenced);
- German pages stay out of the English-configured search index
  (``search: exclude: true`` frontmatter, same convention as
  ``src/platform/devopsguide-de.md``);
- no German page is ever listed in the nav (they are link targets for
  official German documents, not browseable sections);
- every German page cross-links its English twin and vice versa, so
  readers arriving from an official document can navigate both ways.
"""

from __future__ import annotations

import re
import tomllib
from collections.abc import Iterator
from pathlib import Path

import pytest

DOC = Path(__file__).resolve().parents[1]
SRC = DOC / "src"
DE = SRC / "de"
CONFIG = DOC / "zensical.toml"

# [text](target) for both links and images (![alt](target)): footnotes
# ([^name]) carry no parentheses and never match.
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")

EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "tel:")

# search: exclude: true frontmatter (2-space nested YAML)
SEARCH_EXCLUDE_RE = re.compile(r"(?m)^search:\n {2}exclude: true$")


def de_pages() -> list[Path]:
    """All German markdown pages, sorted for stable parametrization."""
    return sorted(DE.rglob("*.md"))


def refs(page: Path) -> Iterator[tuple[str, Path]]:
    """Yield ``(raw_target, resolved_path)`` for every internal ref.

    External URLs and pure fragments are skipped; ``resolved_path`` is
    the raw (non-normalized) join of the page's directory and the
    ref path, as zensical resolves it in the source tree at build time.
    """
    for raw in LINK_RE.findall(page.read_text()):
        if raw.startswith(EXTERNAL_PREFIXES) or raw.startswith("#"):
            continue
        path = raw.split("#", 1)[0]
        if not path:
            continue
        yield raw, page.parent / path


def nav_pages(nav: object) -> Iterator[str]:
    """Yield every page string from the parsed ``nav`` structure."""
    if isinstance(nav, str):
        yield nav
    elif isinstance(nav, dict):
        for value in nav.values():
            yield from nav_pages(value)
    elif isinstance(nav, list):
        for item in nav:
            yield from nav_pages(item)


def en_twin(de_page: Path) -> Path:
    """The English twin of a German page: same path below ``src/``."""
    return SRC / de_page.relative_to(DE)


def rel(path: Path) -> Path:
    """Path relative to ``doc/`` for readable failure output."""
    return path.relative_to(DOC)


@pytest.fixture(params=de_pages(), ids=lambda p: str(rel(p)))
def de_page(request: pytest.FixtureRequest) -> Path:
    return request.param


def test_relative_refs_resolve(de_page: Path) -> None:
    """Every internal ref on a German page hits an existing file in src/."""
    broken = []
    for raw, resolved in refs(de_page):
        normalized = resolved.resolve()
        if not normalized.is_file():
            broken.append(f"{raw} -> {rel(resolved)} (missing)")
        elif SRC.resolve() not in normalized.parents:
            broken.append(f"{raw} -> {rel(resolved)} (escapes src/)")
    assert not broken, f"unresolved refs on {rel(de_page)}:\n" + "\n".join(
        broken
    )


def test_refs_are_relative_not_root_absolute(de_page: Path) -> None:
    """Refs use file-relative source-tree paths, never root-absolute URLs.

    Root-absolute targets would bypass zensical's source-tree link
    resolution entirely (and the build-time validation with it).
    """
    offenders = [raw for raw, _ in refs(de_page) if raw.startswith("/")]
    assert not offenders, f"root-absolute refs on {rel(de_page)}: {offenders}"


def test_search_exclude_frontmatter(de_page: Path) -> None:
    """German content stays out of the English-configured search index."""
    text = de_page.read_text()
    assert text.startswith("---"), f"{rel(de_page)} has no frontmatter"
    frontmatter = text.split("---", 2)[1]
    assert SEARCH_EXCLUDE_RE.search(frontmatter), (
        f"{rel(de_page)} lacks 'search:\\n  exclude: true' frontmatter"
    )


def test_de_pages_stay_out_of_nav() -> None:
    """German pages are unlisted: built, but never sidebar entries."""
    with CONFIG.open("rb") as fh:
        config = tomllib.load(fh)
    listed = [
        page
        for page in nav_pages(config["project"]["nav"])
        if page.startswith("de/")
    ]
    assert not listed, f"nav lists German pages: {listed}"


def test_en_twin_exists(de_page: Path) -> None:
    """A translated page always has its untranslated twin in the tree."""
    twin = en_twin(de_page)
    assert twin.is_file(), f"{rel(de_page)} has no English twin {rel(twin)}"


def test_cross_links_between_twins(de_page: Path) -> None:
    """DE and EN twin link each other (arrival from official docs works)."""
    twin = en_twin(de_page)
    if not twin.is_file():
        pytest.fail(f"{rel(de_page)} has no English twin {rel(twin)}")

    de_targets = {resolved.resolve() for _, resolved in refs(de_page)}
    en_targets = {resolved.resolve() for _, resolved in refs(twin)}

    assert twin.resolve() in de_targets, (
        f"{rel(de_page)} does not link its English twin {rel(twin)}"
    )
    assert de_page.resolve() in en_targets, (
        f"{rel(twin)} does not link its German twin {rel(de_page)}"
    )
