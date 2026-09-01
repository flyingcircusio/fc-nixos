"""Unit tests for the pure helpers of ``tools/checkout_versioned_docs.py``.

The contract suite (``test_checkout_versioned_docs.py``) drives the
tool end-to-end with pages that carry NO frontmatter -- these tests
cover the frontmatter-manipulation branches it cannot reach, plus the
manifest round-trip.
"""

from __future__ import annotations

from pathlib import Path

from tools.checkout_versioned_docs import (
    MANIFEST_NAME,
    frontmatter_with_search_exclude,
    load_manifest,
    namespaced_include,
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
    """Sunsetting archives only the version's own subtree."""
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
