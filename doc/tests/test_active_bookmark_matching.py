"""Tests for the ACTIVE-bookmark local-manual selection.

The contract suites drive both tools e2e; these tests pin the resolver
unit itself and the partial-sunset-move scenario with a setup whose
bookmark state is coherent (the contract's own
``test_partial_move_excludes_stray_files`` leaves the repo WITHOUT an
active bookmark -- ``hg up -r 1`` deactivates it and nothing re-activates
one -- which ``test_no_active_bookmark_fails_loudly`` defines as a
hard-fail state; here the bookmark is re-activated after the partial
move, so the namespaced-export behavior itself is what is under test).
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from tools import checkout_versioned_docs as cot
from tools import gen_platform_versions as gpv

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
def repo(tmp_path: Path) -> Path:
    """Three changesets with pinned bookmarks, current ACTIVE.

    r0: legacy whole doc/src tree, r1: sunset move into doc/src/25.11/,
    r2: dev tree. Same history shape as the contract fixture.
    """
    repo = tmp_path / "repo"
    src = repo / "doc" / "src"
    src.mkdir(parents=True)
    hg(repo, "init")
    (repo / ".hg" / "hgrc").write_text("[ui]\nusername = T <t@x>\n")
    put(src, "index.md")
    put(src, "components/postgresql.md", "# postgresql v1\n")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r0: legacy tree")
    legacy = src / "25.11"
    legacy.mkdir()
    (legacy / "components").mkdir()
    (src / "index.md").rename(legacy / "index.md")
    (src / "components" / "postgresql.md").rename(
        legacy / "components" / "postgresql.md"
    )
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r1: sunset move")
    put(src, "index.md")
    put(src, "components/postgresql.md", "# postgresql v2\n")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r2: dev tree")
    hg(repo, "bookmark", "-r", "0", "fc-26.05-production")
    hg(repo, "bookmark", "-r", "1", "fc-25.11-production")
    hg(repo, "bookmark", "-r", "2", "fc-26.11-dev")
    hg(repo, "up", "fc-26.05-production")
    return repo


def load(
    repo: Path, text: str = TOML, tmp: Path | None = None
) -> gpv.VersionSet:
    path = (tmp or repo.parent) / "platform-versions.toml"
    path.write_text(text)
    return gpv.load_versions(path)


def test_match_active_returns_the_bookmarked_entry(repo: Path) -> None:
    """Active [current] bookmark matches the current entry."""
    matched = gpv.match_active(load(repo), repo)
    assert (matched.ver, matched.status) == ("26.05", "current")


def test_match_active_follows_the_active_bookmark_not_the_category(
    repo: Path,
) -> None:
    """Active prerelease bookmark matches the prerelease entry."""
    hg(repo, "up", "fc-26.11-dev")
    matched = gpv.match_active(load(repo), repo)
    assert (matched.ver, matched.status) == ("26.11", "prerelease")


def test_match_active_without_active_bookmark_fails(repo: Path) -> None:
    """Bare working copy: remediation names hg su, no fallback."""
    hg(repo, "up", "-r", "1")
    with pytest.raises(gpv.ActiveBookmarkError) as excinfo:
        gpv.match_active(load(repo), repo)
    assert "no active bookmark" in str(excinfo.value)
    assert "hg su" in str(excinfo.value)


def test_match_active_with_unknown_bookmark_names_all_revs(repo: Path) -> None:
    """A bookmark no TOML rev carries: error lists it and the known revs."""
    hg(repo, "bookmark", "-r", "2", "feature-x")
    hg(repo, "up", "feature-x")
    with pytest.raises(gpv.ActiveBookmarkError) as excinfo:
        gpv.match_active(load(repo), repo)
    msg = str(excinfo.value)
    assert "feature-x" in msg
    for rev in ("fc-26.05-production", "fc-26.11-dev", "fc-25.11-production"):
        assert rev in msg


def test_active_bookmark_outside_a_repo_fails(tmp_path: Path) -> None:
    """A directory without .hg cannot answer: loud error, no guessing."""
    empty = tmp_path / "not-a-repo"
    empty.mkdir()
    with pytest.raises(gpv.ActiveBookmarkError):
        gpv.active_bookmark(empty)


def test_partial_move_excludes_stray_files_with_active_bookmark(
    repo: Path, tmp_path: Path
) -> None:
    """The partial-sunset scenario, setup with a coherent bookmark state.

    Same history surgery as the contract's
    ``test_partial_move_excludes_stray_files`` -- stray tracked file in
    doc/src/ next to the namespaced tree at the sunset rev -- but with
    fc-26.05-production re-activated afterwards, so the tool has the
    active bookmark its spec requires. The namespaced export must place
    doc/src/25.11/** only: no stray.md, no 25.11/25.11.
    """
    versions_path = tmp_path / "platform-versions.toml"
    src_root = tmp_path / "src"
    put(src_root, "index.md")
    put(src_root, "components/postgresql.md", "# local current\n")

    hg(repo, "up", "-r", "1")
    put(repo / "doc" / "src", "stray.md", "# stray, outside the namespace\n")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "partial move: stray file in doc/src/")
    hg(repo, "bookmark", "-r", "3", "fc-25.11-partial")
    hg(repo, "up", "fc-26.05-production")  # re-activate: local manual is 26.05
    versions_path.write_text(
        TOML.replace("fc-25.11-production", "fc-25.11-partial")
    )

    assert (
        cot.main(
            [
                "--versions",
                str(versions_path),
                "--src",
                str(src_root),
                "--repo",
                str(repo),
            ]
        )
        == 0
    )
    assert (src_root / "25.11" / "components" / "postgresql.md").is_file()
    assert (
        src_root / "26.11" / "components" / "postgresql.md"
    ).read_text() == ("# postgresql v2\n")
    assert not (src_root / "25.11" / "stray.md").exists()
    assert not (src_root / "25.11" / "25.11").exists()
    assert not (src_root / "26.05").exists()
