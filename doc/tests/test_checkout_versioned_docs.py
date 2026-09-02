"""Executable spec for ``tools/checkout_versioned_docs.py``.

The tool places ``[[prerelease]]``/``[[sunsetting]]`` snapshots under
``src/<ver>/`` from LOCAL hg revisions (fixture: a real throwaway hg
repository with bookmarks at two changesets). Pinned behavior:

- the ACTIVE bookmark (``hg su``) is matched against the TOML revs:
  the matched entry IS the local manual and is never checked out; ALL
  other entries become snapshots. ONLY ``[[prerelease]]`` exports the
  whole ``doc/src/**`` tree (the living dev line); every other
  non-matched version -- sunsetting AND ``[current]`` alike -- must
  carry its branch's namespaced ``doc/src/<ver>/**`` tree or fails
  loudly. No active bookmark, or one unknown to the TOML, fails loudly
  -- no fallback of any kind;
- prerelease revisions are exported from the WHOLE ``doc/src/**``;
  sunsetting revisions ONLY from their branch's ``doc/src/<ver>/**``
  (the one-time sunset move commit) -- a missing namespaced tree fails
  loudly with the remediation and NEVER falls back to the whole tree;
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
import shutil
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
      r1 -- fc-26.05-production (current, ACTIVE): tree namespaced
            at doc/src/26.05/** (postgresql v1, only-old)
      r2 -- fc-25.11-production (sunsetting source): tree namespaced
            at doc/src/25.11/** only
      r3 -- fc-26.11-dev (prerelease source): fresh doc/src/** with
            postgresql v2 and platform/users

    doc/ lives OUTSIDE the repo: its src/ is the local manual of the
    ACTIVE bookmark (fc-26.05-production -> matched [current] 26.05)
    with postgresql + redis + index.
    """
    repo = tmp_path / "repo"
    src = repo / "doc" / "src"
    src.mkdir(parents=True)
    hg(repo, "init")
    (repo / ".hg" / "hgrc").write_text(
        "[ui]\nusername = Test <test@example.com>\n"
    )
    legacy = src / "26.05"
    put(legacy, "index.md")
    put(legacy, "components/postgresql.md", "# postgresql v1\n")
    put(legacy, "only-old.md")
    broken = (
        "# broken\n"
        "\n"
        "!!! warning\n"
        "    This is a sunsetting version of the platform documentation."
        " Go to [the current version](../../platform-releases/"
        "fc-26.05-production/broken.md) for optimized support.\n"
        "\n"
        "See [local](../platform/fc-26.05-production/local.md#nixos-local)"
        " for details.\n"
    )
    put(legacy, "components/broken.md", broken)
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r1: 26.05 tree namespaced at doc/src/26.05/**")

    # The 25.11 branch carries its own namespaced tree: a plain dir
    # rename + addremove (rename detection). Explicit -r for the
    # bookmarks: `hg commit` advances the ACTIVE bookmark, so all are
    # pinned after the fact.
    (src / "26.05").rename(src / "25.11")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r2: 25.11 tree namespaced at doc/src/25.11/**")

    # Dev branch replaces the namespaced tree with its own doc/src/**.
    shutil.rmtree(src / "25.11")
    put(src, "index.md")
    put(src, "components/postgresql.md", "# postgresql v2\n")
    put(src, "platform/users.md")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r3: dev tree")
    hg(repo, "bookmark", "-r", "0", "fc-26.05-production")
    hg(repo, "bookmark", "-r", "1", "fc-25.11-production")
    hg(repo, "bookmark", "-r", "2", "fc-26.11-dev")
    # Activate the current bookmark LAST: the ACTIVE bookmark (not any
    # TOML category) defines which entry is the local manual.
    hg(repo, "up", "fc-26.05-production")

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


def test_sunsetting_without_versioned_dir_fails_loudly(
    project: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    """No doc/src/25.11/ in the rev: exit 1, remediation, NO fallback.

    The pre-move changeset (r1) carries only doc/src/** -- pointing the
    sunsetting entry at it must fail loudly instead of silently placing
    the whole tree.
    """
    repo, doc_src, versions = project
    hg(repo, "bookmark", "-r", "0", "fc-25.11-pre-move")
    versions.write_text(
        TOML.replace("fc-25.11-production", "fc-25.11-pre-move")
    )

    assert run(project) == 1
    err = capsys.readouterr().err
    assert "doc/src/25.11" in err
    assert "sunset" in err.lower()
    assert not (doc_src / "25.11").exists()


def test_partial_move_excludes_stray_files(
    project: tuple[Path, Path, Path],
) -> None:
    """Stray files outside doc/src/25.11/ at the sunset rev are ignored.

    A partial (or sloppily managed) sunset move may leave tracked files
    directly in doc/src/** -- the namespaced export must not pick them
    up, and the placement must not degrade into a whole-tree export.
    """
    repo, doc_src, versions = project
    hg(repo, "up", "-r", "1")  # back on the sunset move changeset
    put(repo / "doc" / "src", "stray.md", "# stray, outside the namespace\n")
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "partial move: stray file in doc/src/")
    hg(repo, "bookmark", "-r", "3", "fc-25.11-partial")
    hg(repo, "up", "fc-26.05-production")  # re-activate: the hg up -r 1
    # surgery above deactivated the bookmark the tool now requires
    versions.write_text(TOML.replace("fc-25.11-production", "fc-25.11-partial"))

    assert run(project) == 0
    assert (doc_src / "25.11" / "components" / "postgresql.md").is_file()
    assert not (doc_src / "25.11" / "stray.md").exists()
    assert not (doc_src / "25.11" / "25.11").exists()


def test_active_prerelease_builds_its_manual(
    project: tuple[Path, Path, Path],
) -> None:
    """Active bookmark = prerelease: no self-copy, all others pulled.

    The local tree IS the 26.11 manual; 26.05 arrives as a whole-tree
    snapshot from r1, 25.11 namespaced from r2, and the sunsetting
    banner points at the MATCHED version (26.11).
    """
    repo, doc_src, _ = project
    hg(repo, "up", "fc-26.11-dev")
    assert run(project) == 0

    assert not (doc_src / "26.11").exists()
    assert "26.11" not in manifest_of(project)["versions"]
    assert (
        "# postgresql v1"
        in (doc_src / "26.05" / "components" / "postgresql.md").read_text()
    )
    assert (doc_src / "26.05" / "only-old.md").is_file()
    assert not (doc_src / "26.05" / "25.11").exists()
    assert not (doc_src / "26.05" / "26.05").exists()
    assert (
        "# postgresql v1"
        in (doc_src / "25.11" / "components" / "postgresql.md").read_text()
    )
    assert set(manifest_of(project)["versions"]) == {"26.05", "25.11"}
    text = (doc_src / "25.11" / "components" / "postgresql.md").read_text()
    assert "[26.11 version]" in text


def test_no_active_bookmark_fails_loudly(
    project: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    """Anonymous working copy: exit 1, remediation, nothing placed."""
    repo, doc_src, _ = project
    hg(repo, "up", "-r", "2")  # bare rev: deactivates the bookmark

    assert run(project) == 1
    err = capsys.readouterr().err
    assert "no active bookmark" in err
    assert "hg su" in err
    assert not (doc_src / "26.11").exists()
    assert not (doc_src / "26.05").exists()


def test_unknown_active_bookmark_fails_loudly(
    project: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    """A bookmark the TOML does not know: exit 1 naming it and the revs."""
    repo, doc_src, _ = project
    hg(repo, "bookmark", "-r", "2", "feature-x")
    hg(repo, "up", "feature-x")

    assert run(project) == 1
    err = capsys.readouterr().err
    assert "feature-x" in err
    assert "fc-26.05-production" in err
    assert "fc-26.11-dev" in err
    assert "fc-25.11-production" in err
    assert not (doc_src / "26.11").exists()


def test_non_matched_current_requires_namespaced_tree(
    project: tuple[Path, Path, Path], capsys: pytest.CaptureFixture[str]
) -> None:
    """A non-matched [current] without doc/src/<ver>/: exit 1, no whole
    tree. Pointing current at the dev bookmark (whole doc/src/** only)
    must fail loudly instead of nesting or duplicating the tree."""
    repo, doc_src, versions = project
    versions.write_text(TOML.replace("fc-26.05-production", "fc-26.11-dev"))
    hg(repo, "up", "fc-25.11-production")  # matched = sunsetting 25.11

    assert run(project) == 1
    err = capsys.readouterr().err
    assert "doc/src/26.05" in err
    assert not (doc_src / "26.05").exists()


def test_placement_applies_content_fixes(
    project: tuple[Path, Path, Path],
) -> None:
    """Placed snapshots are link-clean: dead split-era targets fixed,
    old fetch-era banners stripped -- on every placement."""
    _, doc_src, _ = project
    assert run(project) == 0

    text = (doc_src / "25.11" / "components" / "broken.md").read_text()
    assert "platform-releases/" not in text
    assert "This is a sunsetting version" not in text
    assert "](../platform/local.md#nixos-local)" in text


def test_old_current_snapshot_gets_banner_and_exclude(
    project: tuple[Path, Path, Path],
) -> None:
    """26.05 (older than matched 26.11): search-exclude + banner like a
    sunsetting snapshot -- but WITHOUT 'sunsetting' wording, its public
    status is current."""
    repo, doc_src, _ = project
    hg(repo, "up", "fc-26.11-dev")
    assert run(project) == 0

    text = (doc_src / "26.05" / "components" / "broken.md").read_text()
    assert text.startswith("---\n")
    assert "exclude: true" in text.split("!!! warning", 1)[0]
    assert "[26.11 manual]" in text
    assert "is in sunsetting" not in text
