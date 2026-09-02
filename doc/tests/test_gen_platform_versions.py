"""Executable spec for ``tools/gen_platform_versions.py``.

The generator turns ``platform-versions.toml`` plus the ``src/`` file
trees into the committed switcher payload
``src/_static/platform-versions.js``. Four properties pin the design:

- the page inventory is derived from FILE EXISTENCE ONLY -- a page-id
  (tree-relative posix path sans ``.md``) found in at least two trees
  is *versioned* and gets switcher entries; one-tree page-ids are
  common pages with no switcher at all (content-agnostic on purpose:
  ``de/`` pages version exactly like any other page);
- snapshot dirs never leak into the local inventory (``src/26.11/x.md``
  is never a ``26.11/x`` page of the current version);
- the ACTIVE bookmark decides which entry is the local manual: it
  builds at ``/`` (payload ``current``), every other entry -- including
  a non-matched ``[current]`` -- becomes a snapshot at ``/<ver>/``;
- missing snapshots of declared versions and orphan snapshot dirs of
  undeclared versions warn but never fail the run;
- the rendered JS is deterministic and JSON-roundtrips into the exact
  payload dict.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from structlog.testing import capture_logs

from tools import gen_platform_versions as gpv

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


def put(root: Path, rel: str) -> None:
    """Create ``root/<rel>`` as a markdown page (parents as needed)."""
    page = root / rel
    page.parent.mkdir(parents=True, exist_ok=True)
    page.write_text("# page\n")


@pytest.fixture
def doc_tree(tmp_path: Path) -> tuple[Path, Path]:
    """(versions-file, src-dir) with local, 26.11, 25.11 trees + orphan 24.05.

    - ``index`` (root) and ``components/postgresql`` exist in 3 trees ->
      versioned everywhere (root as page-id "", postgresql as-is)
    - ``components/redis`` local + 25.11 -> versioned in both
    - ``platform/users`` local + 26.11 -> versioned in both
    - ``getting-started`` (from getting-started/index.md -- trailing
      index folds away) and ``de/overview`` local only -> common
    - ``24.05/legacy`` orphan snapshot nobody declared
    """
    src = tmp_path / "src"
    for rel in (
        "index.md",
        "components/postgresql.md",
        "components/redis.md",
        "platform/users.md",
        "getting-started/index.md",
        "de/overview.md",
        "26.11/index.md",
        "26.11/components/postgresql.md",
        "26.11/platform/users.md",
        "25.11/index.md",
        "25.11/components/postgresql.md",
        "25.11/components/redis.md",
        "24.05/legacy.md",
    ):
        put(src, rel)
    versions = tmp_path / "platform-versions.toml"
    versions.write_text(TOML)
    return versions, src


def payload_for(
    doc_tree: tuple[Path, Path], matched: gpv.VersionEntry | None = None
) -> dict:
    versions, src = doc_tree
    vset = gpv.load_versions(versions)
    return gpv.build_payload(vset, matched or vset.current, src)


def by_ver(payload: dict) -> dict[str, dict]:
    return {v["ver"]: v for v in payload["versions"]}


def test_payload_structure(doc_tree: tuple[Path, Path]) -> None:
    """Versions appear in canonical order with status, label and index."""
    payload = payload_for(doc_tree)

    assert payload["current"] == "26.05"
    assert [
        (v["ver"], v["status"], v["index"], v["label"])
        for v in payload["versions"]
    ] == [
        ("26.05", "current", "/", "26.05 (current)"),
        ("26.11", "prerelease", "/26.11/", "26.11 (prerelease)"),
        ("25.11", "sunsetting", "/25.11/", "25.11 (sunsetting)"),
    ]


def test_versioned_pages_get_switcher_entries(
    doc_tree: tuple[Path, Path],
) -> None:
    """Page-ids in >=2 trees map to their version's URL prefix.

    The root ``index.md`` folds to page-id "" -- ids are URL-shaped
    because the switcher concatenates ``<prefix><page-id>/``.
    """
    entries = by_ver(payload_for(doc_tree))

    assert entries["26.05"]["pages"] == {
        "": "/",
        "components/postgresql": "/",
        "components/redis": "/",
        "platform/users": "/",
    }
    assert entries["26.11"]["pages"] == {
        "": "/26.11/",
        "components/postgresql": "/26.11/",
        "platform/users": "/26.11/",
    }
    assert entries["25.11"]["pages"] == {
        "": "/25.11/",
        "components/postgresql": "/25.11/",
        "components/redis": "/25.11/",
    }


def test_common_pages_get_no_switcher_entry(
    doc_tree: tuple[Path, Path],
) -> None:
    """One-tree page-ids (incl. de/ pages and orphan trees) appear nowhere."""
    payload = payload_for(doc_tree)
    all_page_ids = {pid for v in payload["versions"] for pid in v["pages"]}

    assert "getting-started" not in all_page_ids
    assert "de/overview" not in all_page_ids
    assert "legacy" not in all_page_ids


def test_snapshot_dirs_never_leak_into_current(
    doc_tree: tuple[Path, Path],
) -> None:
    """Local scan skips src/<NN.NN>/ -- no '26.11/...' page-ids at '/'."""
    payload = payload_for(doc_tree)

    assert not any(
        pid.startswith(("26.11/", "25.11/", "24.05/"))
        for v in payload["versions"]
        for pid in v["pages"]
    )


def test_missing_snapshot_warns_and_lists_empty(
    doc_tree: tuple[Path, Path],
) -> None:
    """A declared version without tree stays listed, empty, with a warning."""
    versions, src = doc_tree
    shutil.rmtree(src / "25.11")

    with capture_logs() as logs:
        payload = payload_for(doc_tree)

    assert by_ver(payload)["25.11"]["pages"] == {}
    assert any(
        event["event"] == "snapshot-missing" and event["ver"] == "25.11"
        for event in logs
    )


def test_orphan_snapshot_dir_warns(doc_tree: tuple[Path, Path]) -> None:
    """An undeclared src/<NN.NN>/ dir warns but does not fail."""
    with capture_logs() as logs:
        payload_for(doc_tree)

    assert any(
        event["event"] == "orphan-snapshot-dir" and event["ver"] == "24.05"
        for event in logs
    )


def test_render_js_roundtrips_payload(doc_tree: tuple[Path, Path]) -> None:
    """The JS body is JSON that parses back into the exact payload."""
    payload = payload_for(doc_tree)
    js = gpv.render_js(payload)

    assert js.startswith("/* Generated by tools/gen_platform_versions.py")
    body = js[js.index("{") : js.rindex("}") + 1]
    assert json.loads(body) == payload
    assert js.endswith("};\n")


def test_main_writes_deterministic_output(
    doc_tree: tuple[Path, Path],
    hg_repo: Path,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """CLI writes the file, and a second run is a no-op (unchanged)."""
    versions, src = doc_tree
    out = tmp_path / "static" / "platform-versions.js"
    argv = [
        "--versions",
        str(versions),
        "--src",
        str(src),
        "--out",
        str(out),
        "--repo",
        str(hg_repo),
    ]

    assert gpv.main(argv) == 0
    first = out.read_text()
    assert '"current": "26.05"' in first

    # main() reconfigures structlog, which would clobber capture_logs --
    # capsys sees the stderr-rendered event instead.
    capsys.readouterr()
    assert gpv.main(argv) == 0
    assert out.read_text() == first
    assert "gen-platform-versions-unchanged" in capsys.readouterr().err


def test_module_invocation_via_python_m(
    doc_tree: tuple[Path, Path], hg_repo: Path, tmp_path: Path
) -> None:
    """The Makefile path works: ``python -m tools.gen_platform_versions``."""
    versions, src = doc_tree
    out = tmp_path / "platform-versions.js"
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "tools.gen_platform_versions",
            "--versions",
            str(versions),
            "--src",
            str(src),
            "--out",
            str(out),
            "--repo",
            str(hg_repo),
        ],
        cwd=DOC,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert '"current": "26.05"' in out.read_text()


@pytest.mark.parametrize(
    ("content", "case", "message"),
    [
        (
            '[[sunsetting]]\nver = "25.11"\nrev = "x"\n',
            "no-current-section",
            r"missing \[current\]",
        ),
        (
            '[current]\nver = "26.5"\nrev = "x"\n',
            "bad-ver-format",
            "must match NN.NN",
        ),
        ('[current]\nver = "26.05"\n', "rev-missing", "non-empty string"),
        (
            TOML
            + '\n[[sunsetting]]\nver = "26.05"\nrev = "fc-26.05-production"\n',
            "duplicate-ver",
            "duplicate ver",
        ),
    ],
)
def test_load_versions_rejects_invalid_toml(
    content: str, case: str, message: str, tmp_path: Path
) -> None:
    """Schema violations fail loudly with a ValueError naming the problem."""
    versions = tmp_path / f"invalid-{case}.toml"
    versions.write_text(content)

    with pytest.raises(ValueError, match=message):
        gpv.load_versions(versions)


def hg(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["hg", *args], cwd=repo, capture_output=True, text=True, check=False
    )
    assert proc.returncode == 0, f"hg {args} failed: {proc.stderr}"
    return proc.stdout


@pytest.fixture
def hg_repo(tmp_path: Path) -> Path:
    """Throwaway repo; bookmarks matching the TOML, current is ACTIVE."""
    repo = tmp_path / "repo"
    repo.mkdir()
    (repo / "file.txt").write_text("x\n")
    hg(repo, "init")
    (repo / ".hg" / "hgrc").write_text(
        "[ui]\nusername = Test <test@example.com>\n"
    )
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r1")
    for name in ("fc-26.05-production", "fc-26.11-dev", "fc-25.11-production"):
        hg(repo, "bookmark", "-r", "0", name)
    hg(repo, "up", "fc-26.05-production")
    return repo


def test_dev_build_labels_matched_version(
    doc_tree: tuple[Path, Path],
) -> None:
    """Active prerelease builds at '/': current becomes the snapshot."""
    versions, _ = doc_tree
    matched = gpv.load_versions(versions).prereleases[0]
    payload = payload_for(doc_tree, matched)

    assert payload["current"] == "26.11"
    entries = by_ver(payload)
    assert entries["26.11"]["index"] == "/"
    assert entries["26.11"]["pages"]["components/postgresql"] == "/"
    assert entries["26.05"]["index"] == "/26.05/"
    assert entries["26.05"]["status"] == "current"
    assert entries["25.11"]["index"] == "/25.11/"


def test_main_fails_without_active_bookmark(
    doc_tree: tuple[Path, Path],
    hg_repo: Path,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """No active bookmark: exit 1 with the hg su remediation."""
    versions, src = doc_tree
    out = tmp_path / "platform-versions.js"
    hg(hg_repo, "up", "null")  # away from any bookmark: deactivates

    code = gpv.main(
        [
            "--versions",
            str(versions),
            "--src",
            str(src),
            "--out",
            str(out),
            "--repo",
            str(hg_repo),
        ]
    )

    assert code == 1
    err = capsys.readouterr().err
    assert "no active bookmark" in err
    assert "hg su" in err
    assert not out.exists()


def test_main_requires_matching_active_bookmark(
    doc_tree: tuple[Path, Path],
    hg_repo: Path,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """Unknown active bookmark: exit 1 naming it and the known revs."""
    versions, src = doc_tree
    out = tmp_path / "platform-versions.js"
    hg(hg_repo, "bookmark", "-r", "0", "feature-x")
    hg(hg_repo, "up", "feature-x")

    code = gpv.main(
        [
            "--versions",
            str(versions),
            "--src",
            str(src),
            "--out",
            str(out),
            "--repo",
            str(hg_repo),
        ]
    )

    assert code == 1
    err = capsys.readouterr().err
    assert "feature-x" in err
    assert "fc-26.11-dev" in err
    assert not out.exists()
