"""Unit and integration tests for ``tools/checkout_versioned_docs.py``.

The contract suite (``test_checkout_versioned_docs.py``) drives the
tool end-to-end; these tests pin the pure helpers (frontmatter
manipulation, banner rendering, manifest round-trip), the
status-aware snapshot annotation with its log events, and the
placement pipeline's content-fix wiring on a minimal hg fixture.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from structlog.testing import capture_logs

from tools.checkout_versioned_docs import (
    MANIFEST_NAME,
    STATUS_CLAUSE,
    banner,
    frontmatter_with_search_exclude,
    load_manifest,
    namespaced_include,
    process_snapshot,
    run_checkout,
    split_frontmatter,
    write_manifest,
)


def test_split_frontmatter_none() -> None:
    """Body without a leading ---: no frontmatter, text unchanged."""
    assert split_frontmatter("# page\n") == ("", "# page\n")


def test_split_frontmatter_with_block() -> None:
    """Leading --- ... --- block splits off with its delimiters."""
    text = "---\ntitle: T\n---\n\n# page\n"
    frontmatter, body = split_frontmatter(text)
    assert frontmatter == "---\ntitle: T\n---\n"
    assert body == "\n# page\n"


def test_split_frontmatter_at_eof() -> None:
    """Frontmatter running to EOF: empty body, no crash."""
    frontmatter, body = split_frontmatter("---\ntitle: T\n---")
    assert frontmatter == "---\ntitle: T\n---"
    assert body == ""


def test_split_frontmatter_unclosed_is_body() -> None:
    """A leading --- without a closing --- line is NOT frontmatter
    (e.g. a stray horizontal rule) -- everything stays in the body."""
    text = "---\nstray rule\n"
    assert split_frontmatter(text) == ("", text)


def test_search_exclude_inserted_after_delimiter() -> None:
    """No search: key yet: the block lands right after the opening ---."""
    assert frontmatter_with_search_exclude("---\ntitle: T\n---\n") == (
        "---\nsearch:\n  exclude: true\ntitle: T\n---\n"
    )


def test_search_exclude_left_alone_when_present() -> None:
    """A pre-existing search: key is not duplicated or rewritten
    (sunsetting trees come from backports that carry our conventions)."""
    text = "---\nsearch:\n  exclude: false\n---\n"
    assert frontmatter_with_search_exclude(text) == text


def test_namespaced_include_pattern() -> None:
    """Non-prerelease snapshots archive only the version's own subtree."""
    assert namespaced_include("25.11") == "doc/src/25.11/**"


def test_manifest_round_trip(tmp_path: Path) -> None:
    """Missing manifest loads as {}; written manifest reads back equal."""
    path = tmp_path / MANIFEST_NAME
    assert load_manifest(path) == {}
    write_manifest(path, {"tool_sha256": "0" * 64, "versions": {}})
    assert load_manifest(path) == {
        "tool_sha256": "0" * 64,
        "versions": {},
    }


def test_banner_links_counterpart() -> None:
    """Counterpart exists in the manual: deep relative link to that page."""
    assert banner(
        "components/x", "25.11", "26.05", True, STATUS_CLAUSE["sunsetting"]
    ) == (
        '!!! warning "Documentation for platform version 25.11"\n'
        "    Platform version 25.11 is in sunsetting -- this page is kept"
        " for reference.\n"
        "    The current documentation for this topic is the"
        " [26.05 version](../../components/x).\n\n"
    )


def test_banner_links_manual_without_counterpart() -> None:
    """No counterpart: the banner falls back to the manual index."""
    assert banner(
        "only-old", "25.11", "26.05", False, STATUS_CLAUSE["sunsetting"]
    ) == (
        '!!! warning "Documentation for platform version 25.11"\n'
        "    Platform version 25.11 is in sunsetting -- this page is kept"
        " for reference.\n"
        "    The current documentation for this topic is the"
        " [26.05 manual](../index).\n\n"
    )


def test_process_snapshot_annotates_sunsetting(tmp_path: Path) -> None:
    """Frontmatter FIRST, banner second, body untouched; sunsetting wording
    and a snapshot-annotated log event carrying status and page count."""
    tree = tmp_path / "25.11"
    page = tree / "components" / "x.md"
    page.parent.mkdir(parents=True)
    page.write_text("# body\n")
    src = tmp_path / "src"
    src.mkdir()

    with capture_logs() as logs:
        count = process_snapshot(tree, "25.11", "sunsetting", "26.05", src)

    text = page.read_text()
    assert text.startswith("---\n")
    assert "exclude: true" in text.split("!!! warning", 1)[0]
    assert "is in sunsetting" in text
    assert "[26.05 manual](../../index)" in text
    assert text.endswith("\n# body\n")
    assert count == 1
    assert any(
        event["event"] == "snapshot-annotated"
        and event["ver"] == "25.11"
        and event["status"] == "sunsetting"
        and event["pages"] == 1
        for event in logs
    )


def test_process_snapshot_old_current_wording(tmp_path: Path) -> None:
    """A non-matched current snapshot: same treatment, but the wording
    never says 'sunsetting' -- its public status is current."""
    tree = tmp_path / "26.05"
    page = tree / "y.md"
    tree.mkdir(parents=True)
    page.write_text("# body\n")
    src = tmp_path / "src"
    src.mkdir()

    count = process_snapshot(tree, "26.05", "current", "26.11", src)

    text = page.read_text()
    assert "is an older version" in text
    assert "is in sunsetting" not in text
    assert "[26.11 manual](../index)" in text
    assert count == 1


def test_status_clause_covers_snapshot_statuses() -> None:
    """Every non-prerelease status has wording; none of the current
    wording may say 'sunsetting'."""
    assert set(STATUS_CLAUSE) == {"current", "sunsetting"}
    assert "sunsetting" not in STATUS_CLAUSE["current"]


def hg(repo: Path, *args: str) -> str:
    proc = subprocess.run(
        ["hg", *args], cwd=repo, capture_output=True, text=True, check=False
    )
    assert proc.returncode == 0, f"hg {args} failed: {proc.stderr}"
    return proc.stdout


OLD_BANNER_PAGE = (
    "# old\n"
    "\n"
    "!!! warning\n"
    "    This is a sunsetting version of the platform documentation."
    " Go to [the current version](../../platform-releases/"
    "fc-26.05-production/legacy.md) for optimized support.\n"
    "\n"
    "See [local](../platform/fc-26.05-production/local.md#nixos-local)"
    " for details.\n"
)


@pytest.fixture
def wired(tmp_path: Path) -> tuple[Path, Path, Path]:
    """(repo, src_root, versions): current 26.05 ACTIVE, sunsetting 25.11.

    Both bookmarks sit on the same changeset, whose doc/src/25.11/ tree
    carries a page with the old fetch-era banner and a dead split-era
    link -- exactly the debt ``snapshot_content_fixes`` exists for.
    """
    repo = tmp_path / "repo"
    ns = repo / "doc" / "src" / "25.11"
    ns.mkdir(parents=True)
    hg(repo, "init")
    (repo / ".hg" / "hgrc").write_text(
        "[ui]\nusername = Test <test@example.com>\n"
    )
    (ns / "legacy.md").write_text(OLD_BANNER_PAGE)
    hg(repo, "addremove")
    hg(repo, "commit", "-m", "r1: namespaced 25.11 tree")
    hg(repo, "bookmark", "-r", "0", "fc-25.11-production")
    hg(repo, "bookmark", "-r", "0", "fc-26.05-production")
    hg(repo, "up", "fc-26.05-production")

    src = tmp_path / "doc" / "src"
    src.mkdir(parents=True)
    versions = tmp_path / "doc" / "platform-versions.toml"
    versions.write_text(
        '[current]\nver = "26.05"\nrev = "fc-26.05-production"\n'
        '\n[[sunsetting]]\nver = "25.11"\nrev = "fc-25.11-production"\n'
    )
    return repo, src, versions


def test_run_checkout_fixes_then_annotates(
    wired: tuple[Path, Path, Path],
) -> None:
    """Placement pipeline on a dirty branch page: link-clean fixes run
    first (old banner stripped, dead target repaired), then the
    search-exclude frontmatter and the new banner land -- each step
    logged with the version it touched."""
    repo, src, versions = wired

    with capture_logs() as logs:
        checked, skipped, pruned = run_checkout(versions, src, repo)

    assert (checked, skipped, pruned) == (1, 0, [])
    text = (src / "25.11" / "legacy.md").read_text()
    assert text.startswith("---\n")
    assert "platform-releases/" not in text
    assert "This is a sunsetting version" not in text
    assert "](../platform/local.md#nixos-local)" in text
    assert '!!! warning "Documentation for platform version 25.11"' in text
    assert "# old" in text
    events = {event["event"]: event for event in logs}
    assert events["checkout-placed"]["ver"] == "25.11"
    assert events["content-fixes-applied"]["ver"] == "25.11"
    assert events["content-fixes-applied"]["pages"] == 1
    assert events["snapshot-annotated"]["ver"] == "25.11"
    assert events["snapshot-annotated"]["status"] == "sunsetting"
    assert events["snapshot-annotated"]["pages"] == 1
