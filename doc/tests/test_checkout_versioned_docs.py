"""Executable spec for ``tools/checkout_versioned_docs.py``.

The tool places ``[[prerelease]]``/``[[sunsetting]]`` snapshots under
``src/<ver>/`` from LOCAL hg revisions (fixture: a real throwaway hg
repository with bookmarks at two changesets). Pinned behavior:

- ``[current]`` is never resolved and never placed -- the local tree
  IS the current version, even if its bookmark does not exist;
- missing bookmarks fail loudly (exit 1, ``pull`` hint on stderr) and
  place nothing;
- sunsetting pages gain ``search: exclude`` frontmatter plus a warning
  banner that links the current counterpart ONLY when it exists in the
  local tree (dead refs would break build-time link validation);
- unchanged node + tool fingerprint = skip (manual tree edits
  survive), fingerprint change = re-place (fresh archive);
- undeclared ``src/<NN.NN>/`` dirs are pruned, manifest rewritten.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from tools import checkout_versioned_docs as cot

DOC = Path(__file__).resolve().parents[1]

TOML = """\
[current]
ver = "26.05"
rev = "fc-26.05-production"

[[prerelease]]
ver = "26.11"
rev = "fc-26.11-dev"

[[sunsetting]]
ver = "25.11"
rev = "fc-25.11-production"
"""


def put(root: Path, rel: str, text: str = "# page\n") -> None:
    page = root / rel
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text(text)


def hg(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["hg", *args], cwd=repo, capture_output=True, text=True, check=False
    )
    assert proc.returncode == 0, f"hg {args} failed: {proc.stderr}"
    return proc.stdout


@pytest.fixture
def project(tmp_path: Path) -> tuple[Path, Path, Path]:
    """(repo, doc-src-dir, versions-file).

    repo history:
      r1 -- fc-25.11-production (sunsetting source): postgresql v1, only-old
      r2 -- fc-26.11-dev (prerelease source): postgresql v2, users added

    doc/ lives OUTSIDE the repo: its src/ is the local (=current 26.05)
    tree with postgresql + redis + index. fc-26.05-production does not
    exist as a bookmark -- and must never be needed.
    """
    repo = tmp_path / "repo"
    src = repo / "doc" / "src"
    src.mkdir(parents=True)
    hg(repo, "init")
    (repo / ".hg" / "hgrc").write_text(
        "[ui]\nusername = Test <test@example.com>\n"
    )
    put(src, "index.md")
    put(src, "components/postgresql.md", "# postgresql v1\n")
    put(src, "only-old.md")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r1")

    put(src, "components/postgresql.md", "# postgresql v2\n")
    put(src, "platform/users.md")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r2")
    # Explicit -r: `hg commit` advances the ACTIVE bookmark, so creating
    # fc-25.11-production right after r1 would drag it onto r2 with the
    # next commit. Pinning both after the fact is deterministic.
    hg(repo, "bookmark", "-r", "0", "fc-25.11-production")
    hg(repo, "bookmark", "-r", "1", "fc-26.11-dev")

    doc = tmp_path / "doc"
    doc_src = doc / "src"
    put(doc_src, "index.md")
    put(doc_src, "components/postgresql.md", "# local current\n")
    put(doc_src, "components/redis.md")
    versions = doc / "platform-versions.toml"
    versions.write_text(TOML)
    return repo, doc_src, versions


def run(project: tuple[Path, Path, Path]) -> int:
    repo, doc_src, versions = project
    return cot.main(
        [
            "--versions",
            str(versions),
            "--src",
            str(doc_src),
            "--repo",
            str(repo),
        ]
    )


def manifest_of(project: tuple[Path, Path, Path]) -> dict:
    _, doc_src, _ = project
    return json.loads((doc_src / cot.MANIFEST_NAME).read_text())


def test_places_snapshots_from_bookmarks(
    project: tuple[Path, Path, Path],
) -> None:
    """26.11 carries r2 content, 25.11 carries r1 content."""
    _, doc_src, _ = project
    assert run(project) == 0

    assert (doc_src / "26.11" / "platform" / "users.md").is_file()
    assert (doc_src / "26.11" / "components" / "postgresql.md").read_text() == (
        "# postgresql v2\n"
    )
    assert not (doc_src / "25.11" / "platform" / "users.md").exists()
    assert (
        "# postgresql v1"
        in (doc_src / "25.11" / "components" / "postgresql.md").read_text()
    )
    assert set(manifest_of(project)["versions"]) == {"26.11", "25.11"}


def test_current_is_never_checked_out(project: tuple[Path, Path, Path]) -> None:
    """No src/26.05/ tree, no manifest entry -- fc-26.05-production is absent."""
    _, doc_src, _ = project
    assert run(project) == 0

    assert not (doc_src / "26.05").exists()
    assert "26.05" not in manifest_of(project)["versions"]


def test_sunsetting_pages_get_frontmatter_and_banner(
    project: tuple[Path, Path, Path],
) -> None:
    """Frontmatter FIRST (zensical parses it only at file start), then
    the banner WITH counterpart link, then the body."""
    _, doc_src, _ = project
    assert run(project) == 0

    text = (doc_src / "25.11" / "components" / "postgresql.md").read_text()
    assert text.startswith("---\n")
    frontmatter = text.split("!!! warning", 1)[0]
    assert "search:" in frontmatter and "exclude: true" in frontmatter
    assert '!!! warning "Documentation for platform version 25.11"' in text
    assert "[26.05 version](../../components/postgresql)" in text
    assert "# postgresql v1" in text


def test_banner_without_counterpart_links_manual_index(
    project: tuple[Path, Path, Path],
) -> None:
    """A page without a current counterpart links the manual index instead."""
    _, doc_src, _ = project
    assert run(project) == 0

    text = (doc_src / "25.11" / "only-old.md").read_text()
    assert "[26.05 manual](../index)" in text
    assert "only-old" not in text.split("\n\n", 1)[0].replace("!!! warning", "")


def test_prerelease_pages_stay_untouched(
    project: tuple[Path, Path, Path],
) -> None:
    """Prerelease snapshots are placed verbatim: no frontmatter, no banner."""
    _, doc_src, _ = project
    assert run(project) == 0

    text = (doc_src / "26.11" / "components" / "postgresql.md").read_text()
    assert text == "# postgresql v2\n"


def test_skip_unchanged_survives_manual_edits(
    project: tuple[Path, Path, Path],
) -> None:
    """Same node + fingerprint: second run skips, manual marker survives."""
    _, doc_src, _ = project
    assert run(project) == 0
    marker = doc_src / "26.11" / "MANUAL-EDIT"
    marker.write_text("keep me\n")

    assert run(project) == 0
    assert marker.read_text() == "keep me\n"


def test_fingerprint_change_forces_replacement(
    project: tuple[Path, Path, Path],
) -> None:
    """A different tool_sha256 in the manifest re-places the tree."""
    _, doc_src, versions = project
    assert run(project) == 0
    manifest_path = doc_src / cot.MANIFEST_NAME
    manifest = json.loads(manifest_path.read_text())
    manifest["tool_sha256"] = "0" * 64
    manifest_path.write_text(json.dumps(manifest))
    (doc_src / "26.11" / "MANUAL-EDIT").write_text("stale\n")

    assert run(project) == 0
    assert not (doc_src / "26.11" / "MANUAL-EDIT").exists()


def test_missing_bookmark_fails_loudly(
    project: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    """An unresolvable rev exits 1, names the rev, hints to pull."""
    repo, doc_src, versions = project
    versions.write_text(
        TOML + '\n[[sunsetting]]\nver = "25.05"\nrev = "fc-25.05-production"\n'
    )

    assert run(project) == 1
    err = capsys.readouterr().err
    assert "fc-25.05-production" in err
    assert "pull" in err
    assert not (doc_src / "25.05").exists()


def test_prunes_orphan_snapshot_dirs(project: tuple[Path, Path, Path]) -> None:
    """Undeclared src/<NN.NN>/ disappears; declared trees stay."""
    _, doc_src, _ = project
    put(doc_src, "24.05/legacy.md")
    assert run(project) == 0

    assert not (doc_src / "24.05").exists()
    assert (doc_src / "26.11").is_dir()


def test_module_invocation_via_python_m(
    project: tuple[Path, Path, Path],
) -> None:
    """The Makefile path works: ``python -m tools.checkout_versioned_docs``."""
    repo, doc_src, versions = project
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "tools.checkout_versioned_docs",
            "--versions",
            str(versions),
            "--src",
            str(doc_src),
            "--repo",
            str(repo),
        ],
        cwd=DOC,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert (doc_src / "26.11").is_dir()
