"""Generate per-release changelog pages from the fc-nixos branch changelogs.

``make release-notes RELEASE=2026_032`` reads the cumulative
``changelog.d/CHANGELOG.md`` of every platform version declared in
``platform-versions.yaml`` (via the same persistent repo cache as
``make fetch``), slices out the ``# Release 2026_032`` section of each
contributing branch, bakes the version into the ``XX.XX`` placeholder
headings, inserts the version subsection under ``## Impact``, and renders
``src/changes/<year>/r<NNN>.md``. Navigation is explicit: the tool keeps the
``# BEGIN/END changes-releases`` block inside the ``nav`` array of every
zensical config (``zensical.toml`` and ``zensical-de.toml`` -- both builds
share the same page paths) in sync: one group per year, index + r-pages --
the Zensical equivalent of the former per-year toctrees.

The generated page follows the hand-maintained format: frontmatter
``Publish Date``, ``## Impact`` with per-version subsections, per-version
``## NixOS <ver> platform`` sections, and ``## Detailed Changes`` with
compare/metadata/channel links. The compare chain is derived from the
production branch history (each release's tip is a "Collect changelog
fragments" commit whose changelog starts with ``# Release <id>``); the
nixpkgs pins come from ``release/versions.json`` at both chain SHAs; the
channel URL comes from the release metadata API
(``my.flyingcircus.io/releases/metadata/<branch>/<release>``).

Releases whose fragment section is empty (no scriv fragments collected)
yield a page with frontmatter + heading only -- the release manager
completes those manually, as before.

The tool never overwrites an existing r-file (``--force`` overrides) and
never commits: the release manager reviews and commits the diff.
"""

import datetime
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.request
from pathlib import Path

import certifi
import structlog

from tools.fetch_platform_docs import (
    CONFIG_TOMLS,
    _FC_NIXOS_REMOTE,
    _FETCH_CACHE_DIR,
    ensure_repo,
    load_config,
    resolve_tips,
    run_command,
)

log = structlog.get_logger()

# Every release section in a branch CHANGELOG.md starts with a level-1
# heading ``# Release YYYY_NNN``; the file is cumulative (newest first).
_RELEASE_HEADING = re.compile(r"^# Release (\d{4}_\d{3})\s*$", re.MULTILINE)

# Level-2 headings inside one release section (``## Impact``,
# ``## NixOS XX.XX platform``, ...).
_SECTION_HEADING = re.compile(r"^## (.+?)\s*$", re.MULTILINE)

_RELEASE_ID = re.compile(r"\d{4}_\d{3}")
_PUBLISH_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")


def split_releases(changelog: str) -> dict[str, str]:
    """Split a branch ``CHANGELOG.md`` into ``{release_id: section_text}``.

    The section text excludes the ``# Release YYYY_NNN`` heading itself.
    Releases without any content map to an empty string.
    """
    matches = list(_RELEASE_HEADING.finditer(changelog))
    sections: dict[str, str] = {}
    for i, match in enumerate(matches):
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(changelog)
        sections[match.group(1)] = changelog[start:end].strip("\n")
    return sections


def parse_section(section: str) -> dict[str, str]:
    """Map ``## heading`` -> body for one release section."""
    blocks: dict[str, str] = {}
    matches = list(_SECTION_HEADING.finditer(section))
    for i, match in enumerate(matches):
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(section)
        blocks[match.group(1).strip()] = section[start:end].strip("\n")
    return blocks


def transform_section(
    blocks: dict[str, str], version: str
) -> tuple[str | None, str | None]:
    """Extract the Impact body and the NixOS platform body of a section.

    The platform heading in the branch changelog always carries the
    ``XX.XX`` placeholder (kept for backport-friendliness); the version is
    baked in at render time, so only the body is returned here.
    """
    impact = blocks.get("Impact")
    platform = None
    for heading, body in blocks.items():
        if heading.startswith("NixOS ") and heading.endswith(" platform"):
            platform = body
            break
    return impact, platform


def impact_block(version: str, body: str) -> str:
    """Render one version's Impact subsection (``### <ver>`` + body).

    A body that already carries ``###`` subsections is passed through
    untouched (defensive: the branch changelog normally keeps flat bullets).
    """
    if body.lstrip().startswith("### "):
        return body
    return f"### {version}\n\n{body}"


def render_release(
    release_id: str,
    publish_date: str,
    impact_blocks: list[tuple[str, str]],
    platform_blocks: list[tuple[str, str]],
    detailed_lines: list[str],
) -> str:
    """Render the r-file body matching the hand-maintained format.

    Sections are separated by two blank lines; the file ends with a trailing
    blank line pair (matching ``src/changes/2026/r031.md``).
    """
    sections: list[str] = []
    if impact_blocks:
        impact = "## Impact\n\n" + "\n\n\n".join(
            impact_block(ver, body) for ver, body in impact_blocks
        )
        sections.append(impact)
    for ver, body in platform_blocks:
        sections.append(f"## NixOS {ver} platform\n\n{body}")
    if detailed_lines:
        sections.append("## Detailed Changes\n\n" + "\n".join(detailed_lines))
    text = (
        f"---\nPublish Date: '{publish_date}'\n---\n\n\n"
        f"# Release {release_id} ({publish_date})\n\n"
    )
    if sections:
        text += "\n\n\n".join(sections) + "\n\n"
    return text


def next_monday(today: datetime.date | None = None) -> datetime.date:
    """The next Monday at or after *today*.

    Release notes publish on Mondays (observed pattern: Thursday release,
    Monday publish). A Monday *today* rolls to the following Monday.
    """
    today = today or datetime.date.today()
    days = (0 - today.weekday()) % 7
    return today + datetime.timedelta(days=days or 7)


def render_year_index(year: int) -> str:
    """Render ``src/changes/<year>/index.md``.

    Navigation lives in the generated ``nav`` block in ``zensical.toml``
    (see :func:`render_changes_nav`); the year index page itself is pure
    prose -- no per-page listing.
    """
    return f"# {year}\n\nReleases performed in {year}.\n"


def update_year_index(changes_root: Path, year: int) -> None:
    """(Re)write the year index page from the canonical template."""
    year_dir = changes_root / str(year)
    year_dir.mkdir(parents=True, exist_ok=True)
    (year_dir / "index.md").write_text(render_year_index(year), encoding="utf-8")


# Markers delimiting the generated changelog releases block inside the nav
# array in ``zensical.toml`` (the Zensical equivalent of the former root
# changelog toctree plus per-year toctrees). ``make release-notes`` and
# ``--update-nav`` rewrite everything between them from the ``src/changes/``
# directory state.
_CHANGES_NAV_BEGIN = "# BEGIN changes-releases"
_CHANGES_NAV_END = "# END changes-releases"


def render_changes_nav(changes_root: Path) -> str:
    """Render the marked changes-releases nav block for ``zensical.toml``.

    One nav group per year directory (newest year first): the year index,
    then its r-pages in ascending order.
    """
    years = (
        sorted(
            (p for p in changes_root.iterdir() if p.is_dir() and p.name.isdigit()),
            key=lambda p: int(p.name),
            reverse=True,
        )
        if changes_root.exists()
        else []
    )
    entries: list[str] = []
    for year_dir in years:
        r_pages = sorted(
            f"changes/{year_dir.name}/{p.name}"
            for p in year_dir.glob("r*.md")
            if p.stem[1:].isdigit()
        )
        pages = [f"changes/{year_dir.name}/index.md", *r_pages]
        entries.append(
            f'{{ "{year_dir.name}" = [\n'
            + ",\n".join(f'      "{p}"' for p in pages)
            + "\n  ] }"
        )
    # No trailing newline: the regex replacement covers exactly
    # BEGIN..END without the newline after END -- a trailing \n here would
    # add one blank line per run (non-idempotent).
    return f"{_CHANGES_NAV_BEGIN}\n" + ",\n".join(entries) + f"\n{_CHANGES_NAV_END}"


def update_changes_nav(nav_path: Path, changes_root: Path) -> bool:
    """Rewrite the marked changes-releases nav block in one zensical config.

    Returns True when the file was rewritten. A missing nav file or missing
    markers log a loud warning and change nothing -- the same skip contract
    as the fetch tool's ``update_platform_nav``.
    """
    if not nav_path.exists():
        log.warning(
            "changes-nav-update-skipped",
            reason="nav file missing",
            path=str(nav_path),
        )
        return False
    text = nav_path.read_text(encoding="utf-8")
    pattern = re.compile(
        re.escape(_CHANGES_NAV_BEGIN) + r".*?" + re.escape(_CHANGES_NAV_END),
        re.DOTALL,
    )
    if not pattern.search(text):
        log.warning(
            "changes-nav-update-skipped",
            reason="markers missing",
            path=str(nav_path),
        )
        return False
    nav_path.write_text(
        pattern.sub(render_changes_nav(changes_root), text), encoding="utf-8"
    )
    log.info("changes-nav-updated", path=str(nav_path))
    return True


def update_changes_nav_configs(config_dir: Path, changes_root: Path) -> bool:
    """Rewrite the changes-releases nav block in EVERY zensical config.

    Both ``zensical.toml`` (EN build) and ``zensical-de.toml`` (DE build)
    carry the generated block and are rewritten from the same
    ``src/changes/`` state. A config that is absent is skipped with an info
    event (legitimate in test fixtures); a present config without markers
    warns loudly via :func:`update_changes_nav`. Returns True when at least
    one config was rewritten.
    """
    updated = False
    for name in CONFIG_TOMLS:
        path = config_dir / name
        if not path.exists():
            log.info("changes-nav-config-absent", path=str(path))
            continue
        updated = update_changes_nav(path, changes_root) or updated
    return updated


def _git_env() -> dict[str, str]:
    """Environment for git subprocesses: point TLS at certifi's CA bundle.

    Mirrors ``tools.fetch_platform_docs._git_env``: the build environment has
    no system CA store, so git's default verification fails against the
    promisor remote of the blob-less cache clone.
    """
    env = dict(os.environ)
    env.setdefault("GIT_SSL_CAINFO", certifi.where())
    return env


def git_show(repo: Path, rev: str, path: str) -> str | None:
    """Content of *path* at *rev* in *repo*, or None when absent."""
    result = subprocess.run(
        ["git", "--no-pager", "-C", str(repo), "show", f"{rev}:{path}"],
        capture_output=True,
        text=True,
        env=_git_env(),
    )
    if result.returncode != 0:
        return None
    return result.stdout


def derive_release_chain(
    repo: Path, branch: str, release_id: str, *, run_fn=run_command
) -> tuple[str, str] | None:
    """The ``(old_sha, new_sha)`` compare chain for *release_id* on *branch*.

    Each release's production tip is a "Collect changelog fragments" commit
    whose ``changelog.d/CHANGELOG.md`` starts with ``# Release <id>``. The
    chain is that commit (new) and the previous such commit (old).
    """
    result = run_fn(
        [
            "git",
            "--no-pager",
            "log",
            "--format=%H",
            "--grep",
            "Collect changelog fragments",
            f"refs/remotes/origin/{branch}",
        ],
        cwd=repo,
        env=_git_env(),
    )
    new_sha: str | None = None
    old_sha: str | None = None
    for sha in result.stdout.split():
        changelog = git_show(repo, sha, "changelog.d/CHANGELOG.md")
        if changelog is None:
            continue
        lines = changelog.splitlines()
        first = lines[0] if lines else ""
        if first == f"# Release {release_id}":
            new_sha = sha
        elif new_sha is not None and first.startswith("# Release "):
            old_sha = sha
            break
    if new_sha is None or old_sha is None:
        return None
    return old_sha, new_sha


def nixpkgs_rev(repo: Path, sha: str) -> str | None:
    """The pinned nixpkgs rev at *sha* (from ``release/versions.json``)."""
    data = git_show(repo, sha, "release/versions.json")
    if data is None:
        return None
    try:
        return json.loads(data)["nixpkgs"]["rev"]
    except (KeyError, json.JSONDecodeError):
        return None


def fetch_channel_url(branch: str, release_id: str) -> str | None:
    """The hydra channel URL for a release from the metadata API.

    Returns None (with a warning) when the API is unreachable or the field
    is missing -- the release manager then fills the link manually.
    """
    url = f"https://my.flyingcircus.io/releases/metadata/{branch}/{release_id}"
    try:
        context = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(url, context=context, timeout=30) as resp:
            data = json.load(resp)
        return data.get("channel_url")
    except Exception as exc:  # noqa: BLE001 -- any failure degrades gracefully
        log.warning("channel-url-fetch-failed", url=url, error=str(exc))
        return None


def render_detailed_changes(
    repo: Path,
    contributing: list[tuple[str, str]],
    release_id: str,
    *,
    run_fn=run_command,
    channel_url_fn=fetch_channel_url,
) -> list[str]:
    """One ``- NixOS <ver>: ...`` line per contributing branch.

    A branch whose chain cannot be derived is skipped with a warning; the
    release manager completes the section manually in that case.
    """
    lines: list[str] = []
    for ver, rev in contributing:
        chain = derive_release_chain(repo, rev, release_id, run_fn=run_fn)
        if chain is None:
            log.warning("detailed-changes-chain-missing", version=ver, branch=rev)
            continue
        old_sha, new_sha = chain
        old_np, new_np = nixpkgs_rev(repo, old_sha), nixpkgs_rev(repo, new_sha)
        parts = [
            "[platform code]("
            f"https://github.com/flyingcircusio/fc-nixos/compare/{old_sha}...{new_sha})"
        ]
        if old_np and new_np:
            parts.append(
                "[nixpkgs/upstream changes]("
                f"https://github.com/flyingcircusio/nixpkgs/compare/{old_np}...{new_np})"
            )
        parts.append(
            f"[metadata](https://my.flyingcircus.io/releases/metadata/{rev}/{release_id})"
        )
        channel_url = channel_url_fn(rev, release_id) if channel_url_fn else None
        if channel_url:
            parts.append(f"[channel url]({channel_url})")
        lines.append(f"- NixOS {ver}: " + ", ".join(parts))
    return lines


def run_generate(
    config_path: Path,
    output: Path,
    release_id: str,
    publish_date: str,
    *,
    force: bool = False,
    cache_dir: Path | None = None,
    remote: str = _FC_NIXOS_REMOTE,
    run_fn=run_command,
    channel_url_fn=fetch_channel_url,
    detailed: bool = True,
) -> Path:
    """Generate the r-file for *release_id* from the branch changelogs.

    Also refreshes the year index page and the generated changes-releases
    nav block in every zensical config (``zensical.toml`` and
    ``zensical-de.toml`` next to the output tree's parent). Returns the
    written r-file path. Raises ``FileExistsError`` when the target exists
    and *force* is False; ``RuntimeError`` when the release is not found in
    any tracked branch changelog.
    """
    if not _RELEASE_ID.fullmatch(release_id):
        raise ValueError(f"release id must be of the form YYYY_NNN: {release_id!r}")
    if not _PUBLISH_DATE.fullmatch(publish_date):
        raise ValueError(
            f"publish date must be of the form YYYY-MM-DD: {publish_date!r}"
        )
    cfg = load_config(config_path)
    branches = [(cfg.stable, f"fc-{cfg.stable}-production")] + [
        (e.ver, e.rev) for e in cfg.archived
    ]
    if cache_dir is None:
        cache_dir = config_path.parent / _FETCH_CACHE_DIR
    repo = ensure_repo(cache_dir, remote, run_fn=run_fn)
    tips = resolve_tips(repo, [rev for _, rev in branches], run_fn=run_fn)

    year, num = release_id.split("_")
    target = output / "changes" / year / f"r{int(num):03d}.md"
    if target.exists() and not force:
        raise FileExistsError(
            f"release page already exists: {target} (use --force to overwrite)"
        )

    impact_blocks: list[tuple[str, str]] = []
    platform_blocks: list[tuple[str, str]] = []
    contributing: list[tuple[str, str]] = []
    for ver, rev in branches:
        sha = tips[rev]
        changelog = git_show(repo, sha, "changelog.d/CHANGELOG.md")
        if changelog is None:
            log.info("branch-changelog-missing", version=ver, branch=rev)
            continue
        sections = split_releases(changelog)
        if release_id not in sections:
            log.info(
                "release-not-in-branch",
                version=ver,
                branch=rev,
                release=release_id,
            )
            continue
        impact, platform = transform_section(parse_section(sections[release_id]), ver)
        if impact:
            impact_blocks.append((ver, impact))
        if platform:
            platform_blocks.append((ver, platform))
        contributing.append((ver, rev))
        log.info(
            "release-section-found",
            version=ver,
            branch=rev,
            release=release_id,
        )

    if not contributing:
        raise RuntimeError(
            f"release {release_id} not found in any tracked branch changelog"
        )

    # r035 pattern: platform sections ascending by version (21.05 before 24.05).
    impact_blocks.sort(key=lambda item: item[0])
    platform_blocks.sort(key=lambda item: item[0])

    detailed_lines = (
        render_detailed_changes(
            repo,
            contributing,
            release_id,
            run_fn=run_fn,
            channel_url_fn=channel_url_fn,
        )
        if detailed
        else []
    )

    text = render_release(
        release_id, publish_date, impact_blocks, platform_blocks, detailed_lines
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    log.info("release-page-written", path=str(target), release=release_id)

    update_year_index(output / "changes", int(year))
    update_changes_nav_configs(output.parent, output / "changes")
    return target


def main(argv: list[str] | None = None) -> int:
    """CLI entry.

    Generate a release page (also refreshes year index + changes nav):

    ``python -m tools.generate_release_notes <config> <output-dir> <RELEASE> [flags]``

    Only refresh the generated changes-releases nav block in every zensical
    config (zensical.toml + zensical-de.toml):

    ``python -m tools.generate_release_notes <config> <output-dir> --update-nav``
    """
    args = list(sys.argv[1:] if argv is None else argv)
    if "--update-nav" in args:
        rest = [a for a in args if a != "--update-nav"]
        if len(rest) != 2:
            log.warning(
                "generate-cli-usage",
                usage="python -m tools.generate_release_notes "
                "<platform-versions.yaml> <output-dir> --update-nav",
            )
            return 2
        output = Path(rest[1])
        ok = update_changes_nav_configs(output.parent, output / "changes")
        return 0 if ok else 1
    if len(args) < 3:
        log.warning(
            "generate-cli-usage",
            usage="python -m tools.generate_release_notes "
            "<platform-versions.yaml> <output-dir> <RELEASE> "
            "[--publish-date YYYY-MM-DD] [--force] [--no-detailed-changes]",
        )
        return 2
    config_path, output, release_id = Path(args[0]), Path(args[1]), args[2]
    publish_date: str | None = None
    force = False
    detailed = True
    i = 3
    while i < len(args):
        if args[i] == "--publish-date" and i + 1 < len(args):
            publish_date = args[i + 1]
            i += 2
        elif args[i] == "--force":
            force = True
            i += 1
        elif args[i] == "--no-detailed-changes":
            detailed = False
            i += 1
        else:
            log.warning("generate-cli-unknown-arg", arg=args[i])
            return 2
    if publish_date is None:
        publish_date = next_monday().isoformat()
    if not _PUBLISH_DATE.fullmatch(publish_date):
        log.error("generate-cli-bad-publish-date", publish_date=publish_date)
        return 2
    run_generate(
        config_path,
        output,
        release_id,
        publish_date,
        force=force,
        channel_url_fn=fetch_channel_url if detailed else None,
        detailed=detailed,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
