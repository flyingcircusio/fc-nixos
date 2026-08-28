"""MyST -> Python-Markdown conversion library for the Zensical port.

Structural, tokenizer-driven conversion: every document is parsed with
markdown-it-py configured by myst-parser (``colon_fence`` enabled;
linkify/substitution/replacements stay off, so the parser never mutates
text before conversion). The output is assembled from the ORIGINAL source
lines guided by ``token.map`` spans -- non-MyST segments (emphasis, hard
breaks, list markers, indentation) are emitted byte-identical, code fence
content is never touched, and only MyST constructs are rewritten:

* ``  (label)=`` before a heading  -> heading gains an attr_list id
  ``{ #label }`` (an existing ``{ ... }`` suffix is replaced);
* standalone ``  (label)=``        -> raw HTML anchor ``<a id="label"></a>``
* colon-fence (``:::{note}``) and backtick (```` ```{note} ````)
  admonitions -> ``!!! type`` pymdownx admonitions with the body
  recursively converted and indented by 4 spaces; custom title args
  (``:::{note} Title``) have no ``!!!`` equivalent and are logged, never
  silently ignored;
* ```` ```{code-block} lang ```` -> a plain ```` ```lang ```` fence --
  dropped options (``:caption:``) are logged with a running converter
  counter, never silent;
* ```` ```{toctree} ```` blocks are REMOVED (navigation is explicit in
  ``zensical.toml``), ```` ```{image} path ```` with ``:alt:/`:class:``
  -> ``![alt](path){.cls}`` (unsupported options like ``:width:`` are
  logged), ```` ```{rubric}`` -> ``####````,
  ```` ```{eval-rst}`` blocks are dropped with a loud log event;
* inline roles: ``{ref}``/``{doc}`` become relative Markdown links
  resolved against the tree-wide label map; ``{file}``, ``{command}``,
  ``{program}``, ``{code}``, ``{manpage}``, ``{port}``, ``{version}`` and
  ``{literal}`` become plain code spans; ``{kbd}`` becomes ``++key++``;
  known role patterns inside inline code spans stay raw -- the token
  stream decides what a code span is, never regex over the raw text;
* fragment-only Markdown links ``[text](#label)`` resolve against the
  same tree-wide label map (MyST gave them project-wide meaning via the
  Sphinx label registry): a label defined in ANOTHER file becomes a
  relative URL, an empty display text takes the label string, and
  same-file or unknown fragments stay untouched (legitimate same-page
  heading ids);
* unknown directives and roles pass through RAW and log a warning with
  the construct name and file -- the catch-all inventory for a first run;
* unknown labels log a warning and degrade to a dead ``#label`` fragment.

Label resolution: :func:`collect_label_map` scans raw MyST content keyed
by FINAL tree-relative paths and maps every target the tokenizer
recognises to ``(file, "#label")`` -- the anchor is always the label
itself because the conversion attaches it to the heading (attr_list) or
as an explicit HTML anchor. The two converted forms are recognised as
definitions too, so re-converting an already-converted tree resolves the
same labels.
"""

import re
import sys
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import PurePosixPath
from typing import Any

import structlog
from markdown_it import MarkdownIt
from markdown_it.token import Token
from myst_parser.config.main import MdParserConfig
from myst_parser.parsers.mdit import create_md_parser

log = structlog.get_logger()


# --- tokenizer -----------------------------------------------------------------


class _TokenStreamRenderer:
    """Renderer stub: the converter consumes the token stream, never renders."""

    __output__ = "myst-convert"

    def __init__(self, parser: MarkdownIt) -> None:
        self.parser = parser

    def render(
        self,
        tokens: Sequence[Token],
        options: Mapping[str, Any],
        env: Mapping[str, Any],
    ) -> str:
        return ""


def _build_parser() -> MarkdownIt:
    """MarkdownIt with MyST syntax (colon fences), text mutation disabled.

    ``enable_extensions={"colon_fence"}`` keeps every text-mutating feature
    (linkify, substitution, replacements/smartquotes) off: bare URLs,
    ``(c)`` and ``{{ version }}`` tokens reach the converter byte-identical.
    """
    return create_md_parser(
        MdParserConfig(enable_extensions={"colon_fence"}), _TokenStreamRenderer
    )


_PARSER = _build_parser()


# --- inline constructs -----------------------------------------------------------

# MyST cross-reference roles.
_REF_DISPLAY = re.compile(r"\{ref\}`([^<`]+)<([^>`]+)>`")
_REF_BARE = re.compile(r"\{ref\}`([^`]+)`")
_DOC_ROLE = re.compile(r"\{doc\}`([^`]+)`")

# Roles that degrade to a plain code span.
_CODE_SPAN_ROLES = (
    "file",
    "command",
    "program",
    "code",
    "manpage",
    "port",
    "version",
    "literal",
)

# Kbd role -> pymdownx.keys ++key++ syntax.
_KBD_ROLE = re.compile(r"\{kbd\}`([^`]+)`")

# Role names the converter rewrites; every other role the tokenizer finds
# passes through raw with an inventory warning (catch-all for a first run).
_KNOWN_ROLES = frozenset({"ref", "doc", "kbd", *_CODE_SPAN_ROLES})

# Fragment-only Markdown link ``[text](#anchor)``: rewritten when the
# anchor names a label defined in ANOTHER file. Same-file and unknown
# fragments stay as written (legitimate same-page heading ids); images
# (``![...](...)``) never match.
_ANCHOR_LINK = re.compile(r"(?<!!)\[([^\]]*)\]\(#([^)\s]+)\)")


# --- block constructs ------------------------------------------------------------

# Directive fence info string: ``{name} args`` (plain code fences carry
# the language directly and do not match).
_DIRECTIVE_INFO = re.compile(r"^\{([a-zA-Z][a-zA-Z0-9_+:!-]*)\}(.*)$")

# A closing fence line: only the marker run, no info string.
_BARE_FENCE = re.compile(r"^\s*([:`~]{3,})\s*$")

# ``:name: value`` directive option line (code-block options).
_OPTION_LINE = re.compile(r"^:([a-zA-Z][a-zA-Z0-9_-]*):\s*(.*)$")

# Trailing attr_list on a heading line, replaced when a label attaches.
_ATTR_LIST_SUFFIX = re.compile(r"\s*\{[^}]*\}\s*$")

# An id inside an attr_list brace group: ``#id`` as the first word or after
# whitespace (``{ #id .cls }``, ``{#id}``) -- the form the conversion itself
# emits for labels attached to headings.
_ATTR_LIST_ID = re.compile(r"(?:^|[\s{])#([A-Za-z0-9_][A-Za-z0-9_-]*)")

# Explicit HTML anchor the conversion emits for standalone labels, matched
# against ``html_inline`` token children (never raw text -- code spans and
# fence content cannot produce one).
_HTML_ANCHOR_ID = re.compile(r'^<a id="([A-Za-z0-9_][A-Za-z0-9_-]*)"')

# Admonition types recognised by the Material-lineage theme family.
_ADMONITION_TYPES = frozenset(
    {
        "note",
        "warning",
        "tip",
        "important",
        "caution",
        "hint",
        "danger",
        "error",
        "info",
        "attention",
    }
)


@dataclass(frozen=True, slots=True)
class LabelTarget:
    """Resolution target of one MyST label in the merged tree."""

    rel: str
    anchor: str


def _relative_url(from_file: str, target: LabelTarget) -> str:
    """Markdown link URL from *from_file* (tree-relative, with .md) to target.

    Pure-posix, deterministic, keeps the ``.md`` suffix -- Zensical rewrites
    ``.md`` links to ``.html`` (directory URLs) at build time.
    """
    src_dir = PurePosixPath(from_file).parent
    rel = PurePosixPath(target.rel)
    if src_dir == PurePosixPath("."):
        url = str(rel)
    else:
        depth = len(src_dir.parts)
        url = "/".join([".."] * depth + [str(rel)])
    if target.anchor:
        url += f"#{target.anchor}"
    return url


def collect_label_map(contents: Mapping[str, str]) -> dict[str, LabelTarget]:
    """Scan ``contents`` (final tree-rel path -> text) for label definitions.

    Recognised definitions, all located via the token stream (fence and
    code-span content never counts):

    * raw MyST targets ``  (label)=`` (``myst_target`` tokens);
    * the CONVERTED forms the conversion itself emits -- heading attr_list
      ids (``# Heading { #label }``) and explicit HTML anchors
      (``<a id="label"></a>``) -- so re-converting an already-converted
      tree resolves the same labels.

    The FIRST definition of a label wins -- keys are visited in sorted
    order, so the alphabetically first file decides across all forms:
    ``platform-releases/fc-25.11-production/...`` sorts BEFORE
    ``platform/fc-26.05-production/...`` (``-`` sorts before ``/``), and
    the insertion order of the mapping is irrelevant. Later duplicates
    log a warning, mirroring the duplicate-label scoping the Sphinx build
    used to do explicitly.
    """
    labels: dict[str, LabelTarget] = {}

    def define(label: str, rel: str) -> None:
        if label in labels:
            log.warning(
                "myst-label-duplicate",
                label=label,
                first=labels[label].rel,
                second=rel,
            )
            return
        labels[label] = LabelTarget(rel=rel, anchor=label)

    for rel in sorted(contents):
        tokens = _PARSER.parse(contents[rel])
        for idx, token in enumerate(tokens):
            if token.type == "myst_target":
                define(token.content, rel)
            elif token.type == "heading_open":
                nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
                if nxt is None or nxt.type != "inline":
                    continue
                attr_list = _ATTR_LIST_SUFFIX.search(nxt.content)
                if attr_list is None:
                    continue
                ident = _ATTR_LIST_ID.search(attr_list.group(0))
                if ident is not None:
                    define(ident.group(1), rel)
            elif token.type == "inline":
                for child in token.children or []:
                    if child.type != "html_inline":
                        continue
                    anchor = _HTML_ANCHOR_ID.match(child.content)
                    if anchor is not None:
                        define(anchor.group(1), rel)
    return labels


def _indent_body(block: str) -> str:
    """Admonition body spec: non-blank lines gain 4 spaces, blank lines stay."""
    return "".join(
        ("    " + line) if line.strip() else line
        for line in block.splitlines(keepends=True)
    )


class _Converter:
    """Structural MyST -> Python-Markdown converter for one file.

    Walks the markdown-it token stream and assembles the output from the
    original source lines: fence/colon-fence directives, label targets and
    inline-role spans are located via ``token.map`` line ranges; every
    other segment is emitted byte-identical from the source text.
    """

    def __init__(self, file_rel: str, labels: Mapping[str, LabelTarget]) -> None:
        self.file_rel = file_rel
        self.labels = labels
        self.eval_rst_dropped = 0
        self.codeblock_options_dropped = 0
        self.unknown_labels: list[str] = []

    # -- inline roles -----------------------------------------------------------

    def _ref_url(self, label: str) -> str:
        target = self.labels.get(label)
        if target is None:
            self.unknown_labels.append(label)
            log.warning("myst-label-unknown", label=label, file=self.file_rel)
            return f"#{label}"
        return _relative_url(self.file_rel, target)

    def _convert_inline(self, segment: str, inline: Token | None = None) -> str:
        """Rewrite the roles and fragment links in one inline *segment*.

        The segment may span soft breaks. Non-role text passes through
        byte-identical; role content wrapping across a soft line break
        collapses to a single space, mirroring the tokenizer's own
        role-content handling. Code spans are taken from the token stream
        (``code_inline`` children of *inline*): they are masked out before
        the role regexes run and restored afterwards, so a known role
        pattern inside a code span stays raw -- the token stream decides
        what a code span is, never regex over the raw text. Fragment-only
        Markdown links ``[text](#label)`` resolve against the label map
        like ``{ref}`` roles (see :func:`collect_label_map`).
        """
        masked = segment
        restore: list[str] = []
        pos = 0  # search start: children arrive in document order
        for child in (inline.children if inline is not None else None) or []:
            if child.type != "code_inline":
                continue
            # raw span: markup + optionally space-padded content + markup
            # (CommonMark strips one leading/trailing space of code content)
            pattern = re.compile(
                rf"{re.escape(child.markup)} ?{re.escape(child.content)} ?"
                rf"{re.escape(child.markup)}"
            )
            found = pattern.search(masked, pos)
            if found is None:
                continue  # raw span not recoverable: leave the text exposed
            placeholder = f"\x00{len(restore)}\x00"
            restore.append(found.group(0))
            masked = masked[: found.start()] + placeholder + masked[found.end() :]
            pos = found.start() + len(placeholder)

        def flat(content: str) -> str:
            return content.replace("\n", " ").strip()

        def ref_display(match: re.Match) -> str:
            display, label = flat(match.group(1)), flat(match.group(2))
            return f"[{display}]({self._ref_url(label)})"

        def ref_bare(match: re.Match) -> str:
            label = flat(match.group(1))
            return f"[{label}]({self._ref_url(label)})"

        def doc_role(match: re.Match) -> str:
            content = flat(match.group(1))
            if "<" in content:
                display, _, path = content.rpartition("<")
                display = display.strip()
                path = path.rstrip(">").strip()
            else:
                display = path = content
            path = path.lstrip("/")
            if not path.endswith(".md"):
                path += ".md"
            target = LabelTarget(rel=path, anchor="")
            return f"[{display}]({_relative_url(self.file_rel, target)})"

        def code_span(match: re.Match) -> str:
            return f"`{flat(match.group(1))}`"

        def kbd_role(match: re.Match) -> str:
            return f"++{flat(match.group(1))}++"

        def anchor_link(match: re.Match) -> str:
            display, anchor = match.group(1), match.group(2)
            target = self.labels.get(anchor)
            if target is None or target.rel == self.file_rel:
                return match.group(0)  # unknown or same-file: same-page id
            log.debug(
                "myst-anchor-link-resolved",
                anchor=anchor,
                file=self.file_rel,
                target=target.rel,
            )
            return f"[{display or anchor}]({_relative_url(self.file_rel, target)})"

        masked = _REF_DISPLAY.sub(ref_display, masked)
        masked = _REF_BARE.sub(ref_bare, masked)
        masked = _DOC_ROLE.sub(doc_role, masked)
        for role in _CODE_SPAN_ROLES:
            masked = re.sub(rf"\{{{role}\}}`([^`]+)`", code_span, masked)
        masked = _KBD_ROLE.sub(kbd_role, masked)
        # After the roles: fragment links resolve against the same label
        # map (and links the role handling already rewrote carry a path,
        # so they cannot match again).
        masked = _ANCHOR_LINK.sub(anchor_link, masked)
        for idx, raw_span in enumerate(restore):
            masked = masked.replace(f"\x00{idx}\x00", raw_span)
        return masked

    def _warn_unknown_roles(self, inline: Token) -> None:
        """Inventory roles the tokenizer found but the converter does not know.

        Warning source is the token stream (not regex): `` `{name}` `` inside
        code spans is ``code_inline`` to the tokenizer and stays quiet.
        """
        for child in inline.children or []:
            name = child.meta.get("name") if child.type == "myst_role" else None
            if name is not None and name.lower() not in _KNOWN_ROLES:
                log.warning("myst-role-unknown", role=name, file=self.file_rel)

    # -- block conversion via token stream ---------------------------------------

    def convert(self, text: str) -> str:
        lines = text.splitlines(keepends=True)
        tokens = _PARSER.parse(text)
        out: list[str] = []
        cursor = 0  # first source line not emitted yet
        pending_label: tuple[str, int] | None = None  # (label, target start)

        def flush(upto: int) -> None:
            nonlocal cursor
            out.extend(lines[cursor:upto])
            cursor = upto

        for idx, token in enumerate(tokens):
            if token.map is None or token.map[0] < cursor:
                continue  # span already covered by a previous construct
            start, end = token.map
            if token.type == "myst_target":
                nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
                flush(start)
                if nxt is not None and nxt.type == "heading_open":
                    # Attach to the heading: the target line and the blank
                    # gap up to the heading are dropped entirely.
                    pending_label = (token.content, start)
                else:
                    out.append(f'<a id="{token.content}"></a>\n')
                    cursor = end
            elif token.type == "heading_open":
                if pending_label is None:
                    continue  # heading text converts via its inline token
                label, target_start = pending_label
                pending_label = None
                cursor = target_start
                nxt = tokens[idx + 1] if idx + 1 < len(tokens) else None
                heading_inline = (
                    nxt if nxt is not None and nxt.type == "inline" else None
                )
                out.append(
                    self._heading_with_label(lines[start:end], label, heading_inline)
                )
                cursor = end
            elif token.type in ("fence", "colon_fence"):
                flush(start)
                out.extend(self._convert_fence(token, lines))
                cursor = end
            elif token.type == "inline":
                flush(start)
                self._warn_unknown_roles(token)
                out.append(self._convert_inline("".join(lines[start:end]), token))
                cursor = end
        out.extend(lines[cursor:])
        return "".join(out)

    def _heading_with_label(
        self,
        heading_lines: Sequence[str],
        label: str,
        inline: Token | None = None,
    ) -> str:
        segment = "".join(heading_lines)
        newline = "\n" if segment.endswith("\n") else ""
        stripped = _ATTR_LIST_SUFFIX.sub("", segment.rstrip("\n"))
        return self._convert_inline(stripped, inline) + f" {{ #{label} }}{newline}"

    # -- directive fences ---------------------------------------------------------

    def _convert_fence(self, token: Token, lines: Sequence[str]) -> list[str]:
        assert token.map is not None  # block tokens always carry line spans
        open_line, span_end = token.map
        info = _DIRECTIVE_INFO.match(token.info)
        if info is None:
            # Plain code fence: content stays untouched, byte-identical.
            return list(lines[open_line:span_end])
        name = info.group(1).lower()
        args = info.group(2).strip()

        marker = token.markup[0]
        close_line = span_end - 1
        if not _BARE_FENCE.match(lines[close_line]) or not lines[
            close_line
        ].lstrip().startswith(marker):
            # Unterminated at EOF: no closing fence line to drop.
            close_line = span_end
        if token.type == "colon_fence" and close_line > open_line + 1:
            # Author-intent close: the sources open with ``::::`` but close
            # with ``:::`` -- a shorter run the tokenizer refuses to accept.
            # Closing there (and re-converting the swallowed remainder)
            # matches the writer's intent; well-formed fences are unaffected
            # because their shorter closes cannot appear inside the span.
            open_len = len(token.markup)
            for ln in range(open_line + 1, close_line):
                bare = _BARE_FENCE.match(lines[ln])
                if (
                    bare is not None
                    and lines[ln].lstrip().startswith(marker)
                    and len(bare.group(1)) < open_len
                ):
                    close_line = ln
                    break
        body = lines[open_line + 1 : close_line]
        leftover = lines[close_line + 1 : span_end]

        out: list[str]
        match name:
            case "toctree":
                out = []  # removed entirely: nav lives in zensical.toml
            case "eval-rst":
                self.eval_rst_dropped += 1
                log.warning("myst-eval-rst-dropped", file=self.file_rel)
                out = []
            case "image":
                out = [self._convert_image(args, body)]
            case "rubric":
                out = [f"#### {args}\n"]
            case "code-block":
                out = self._convert_codeblock(args, body)
            case _ if name in _ADMONITION_TYPES:
                if args:
                    # custom title: the ``!!! type`` form cannot express it
                    log.warning(
                        "myst-admonition-args-ignored", args=args, file=self.file_rel
                    )
                opener = lines[open_line]
                indent = opener[: len(opener) - len(opener.lstrip())]
                out = [f"{indent}!!! {name}\n"]
                out.append(_indent_body(self.convert("".join(body))))
            case _:
                log.warning(
                    "myst-directive-unknown", directive=name, file=self.file_rel
                )
                return list(lines[open_line:span_end])
        if leftover:
            out.append(self.convert("".join(leftover)))
        return out

    def _convert_image(self, target: str, body: Sequence[str]) -> str:
        """Image directive -> Markdown image; unsupported options are logged."""
        alt = ""
        classes: list[str] = []
        for raw in body:
            option = _OPTION_LINE.match(raw.strip())
            if option is None:
                continue
            name, value = option.group(1), option.group(2).strip()
            match name:
                case "alt":
                    alt = value
                case "class":
                    classes = value.split()
                case _:
                    log.warning(
                        "myst-image-option-dropped", option=name, file=self.file_rel
                    )
        attrs = ""
        if classes:
            attrs = "{ " + " ".join(f".{c}" for c in classes) + " }"
        return f"![{alt}]({target}){attrs}\n"

    def _convert_codeblock(self, lang: str, body: Sequence[str]) -> list[str]:
        content_start = 0
        options_dropped = False
        for idx, raw in enumerate(body):
            stripped = raw.strip()
            if stripped == "":
                if options_dropped:
                    content_start = idx + 1  # separator blank after options
                break
            option = _OPTION_LINE.match(stripped)
            if option is not None:
                self.codeblock_options_dropped += 1
                log.warning(
                    "myst-codeblock-option-dropped",
                    option=option.group(1),
                    file=self.file_rel,
                    dropped=self.codeblock_options_dropped,
                )
                options_dropped = True
                content_start = idx + 1
            else:
                break
        return [f"```{lang}\n", *body[content_start:], "```\n"]


def convert_myst(text: str, *, file_rel: str, labels: Mapping[str, LabelTarget]) -> str:
    """Convert one MyST document at tree-relative *file_rel* to Python Markdown."""
    return _Converter(file_rel, labels).convert(text)


def convert_tree(
    docs_root, *, skip_parts: frozenset[str] = frozenset({"locales"})
) -> int:
    """Convert every ``.md`` under *docs_root* in place; return the file count.

    Labels resolve across the WHOLE tree (first definition wins, sorted
    order -- platform-releases/... precedes platform/... alphabetically
    because ``-`` sorts before ``/``). Directories named
    in *skip_parts* are left untouched.
    """
    from pathlib import Path

    root = Path(docs_root)
    md_files = sorted(
        p
        for p in root.rglob("*.md")
        if not (skip_parts & set(p.relative_to(root).parts[:-1]))
    )
    contents = {
        p.relative_to(root).as_posix(): p.read_text(encoding="utf-8") for p in md_files
    }
    labels = collect_label_map(contents)
    converted = 0
    for rel, text in contents.items():
        new_text = convert_myst(text, file_rel=rel, labels=labels)
        if new_text != text:
            (root / rel).write_text(new_text, encoding="utf-8")
            converted += 1
    log.info(
        "myst-convert-tree-finished",
        root=str(root),
        files=len(contents),
        converted=converted,
        labels=len(labels),
    )
    return converted


def main(argv: list[str] | None = None) -> int:
    """CLI entry: ``python -m tools.myst_convert <docs-root>`` (in-place)."""
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 1:
        log.warning(
            "myst-convert-usage",
            args=args,
            usage="python -m tools.myst_convert <docs-root>",
        )
        return 2
    convert_tree(args[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
