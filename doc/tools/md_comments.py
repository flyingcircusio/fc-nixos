"""MyST ``%`` comment line stripper — build-side Markdown preprocessor.

MyST comments (lines whose stripped form starts with ``%``) are not part of
Python-Markdown's syntax, so they would render as visible text in the HTML
output. This preprocessor strips them before parsing.

Fence-aware: content inside fenced code blocks (`` ``` `` and ``~~~``,
CommonMark semantics) is never touched. Runs before
``zensical.extensions.macros`` (priority 35) so Jinja2 syntax in comment
lines is never rendered.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from markdown import Extension
from markdown.preprocessors import Preprocessor

if TYPE_CHECKING:
    from markdown import Markdown

#: Runs before zensical.extensions.macros (35) — Jinja2 must never see
#: comment lines. Above every built-in preprocessor except footnotes (50).
PRIORITY = 40


def strip_comment_lines(lines: list[str]) -> list[str]:
    """Strip MyST ``%`` comment lines outside fenced code blocks.

    Pure helper shared with the reference-inventory collector
    (``tools.ref_graphs``): the fence grammar (CommonMark `` ``` `` /
    ``~~~``, same char + at least the opening length to close, nothing
    but whitespace after) lives here once so the build-side stripper and
    the collector always agree on what a comment line is.
    """
    result: list[str] = []
    fence_char: str | None = None
    fence_len = 0
    for line in lines:
        stripped = line.strip()
        if fence_char is not None:
            # Inside a fence: only a closing fence (same char, at least
            # the opening length, nothing but whitespace after) ends it.
            if stripped.startswith(fence_char):
                run = len(stripped) - len(stripped.lstrip(fence_char))
                if run >= fence_len and not stripped[run:].strip():
                    fence_char = None
            result.append(line)
            continue
        # Outside a fence: opening fence = 3+ backticks or tildes.
        if stripped.startswith(("```", "~~~")):
            marker = stripped[0]
            run = len(stripped) - len(stripped.lstrip(marker))
            if run >= 3:
                fence_char = marker
                fence_len = run
            result.append(line)
            continue
        if stripped.startswith("%"):
            continue  # MyST comment line — strip silently
        result.append(line)
    return result


class MdCommentsPreprocessor(Preprocessor):
    """Strip MyST ``%`` comment lines outside fenced code blocks."""

    name = "md-comments"

    def run(self, lines: list[str]) -> list[str]:
        return strip_comment_lines(lines)


class MdCommentsExtension(Extension):
    """Register the MyST comment stripper before the macros preprocessor."""

    name = "md_comments"

    def extendMarkdown(self, md: Markdown) -> None:
        md.registerExtension(self)
        md.preprocessors.register(
            MdCommentsPreprocessor(md), MdCommentsPreprocessor.name, PRIORITY
        )


def makeExtension(**kwargs: object) -> MdCommentsExtension:
    """Python-Markdown extension factory."""
    return MdCommentsExtension(**kwargs)
