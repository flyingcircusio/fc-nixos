"""Guard: no dead layout refs in the doc source tree.

Imported docs must not reference the retired split-layout shapes
(``platform-releases/<branch>/...`` and ``../platform/<branch>/...``).
These died with the fetch-era layout; every page now lives in the unified
tree at ``src/``. Full external URLs (https://doc.flyingcircus.io/...)
are historical changelog content and deliberately out of scope.

Also guards against mangled Sphinx/RST remnants: ``<project:...>`` roles
and backticked ``text <some-label>`` refs.
"""

from __future__ import annotations

import re
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"

# markdown link/image targets: [text](target) and ![alt](target)
TARGET_RE = re.compile(r"\]\(([^)\s]+)\)")

DEAD_SHAPES = (
    # (../)*platform-releases/<branch>/...
    re.compile(r"(^|/)platform-releases/"),
    # (../)+platform/fc-<branch>/...
    re.compile(r"^(\.\./)+platform/fc-"),
)

RST_PROJECT_ROLE_RE = re.compile(r"<project:")
BACKTICKED_REF_RE = re.compile(r"`[^`\n]*<nixos-[a-z0-9-]+>`")

VERSION_DIR_RE = re.compile(r"^[0-9]{2}\.[0-9]{2}$")


def md_files(root: Path):
    """All .md files, excluding checked-out snapshot trees (src/<NN.NN>/)."""
    for path in sorted(root.rglob("*.md")):
        first = path.relative_to(root).parts[0]
        if VERSION_DIR_RE.match(first):
            continue
        yield path


def line_offenders(path: Path, predicate):
    text = path.read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        if predicate(line):
            yield f"{path.relative_to(SRC)}:{lineno}: {line.strip()}"


def test_no_dead_layout_refs():
    offenders = []
    for md in md_files(SRC):
        text = md.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            for target in TARGET_RE.findall(line):
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                if any(shape.search(target) for shape in DEAD_SHAPES):
                    offenders.append(
                        f"{md.relative_to(SRC)}:{lineno}: {target}"
                    )
    assert not offenders, "dead layout refs:\n" + "\n".join(offenders)


def test_no_rst_project_roles():
    offenders = [
        hit
        for md in md_files(SRC)
        for hit in line_offenders(md, RST_PROJECT_ROLE_RE.search)
    ]
    assert not offenders, "mangled RST <project:...> roles:\n" + "\n".join(
        offenders
    )


def test_no_backticked_ref_roles():
    offenders = [
        hit
        for md in md_files(SRC)
        for hit in line_offenders(md, BACKTICKED_REF_RE.search)
    ]
    assert not offenders, (
        "mangled Sphinx :ref: remnants (backticked label refs):\n"
        + "\n".join(offenders)
    )
