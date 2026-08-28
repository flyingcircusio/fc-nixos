"""Local consistency guard for the fetched platform docs tree.

This is the pure-local check behind ``make check-platform`` -- a prerequisite
of the build (``html``/``html-de``) and translation (``update-translations``)
targets. It reads four things, all on disk and with NO network and NO git:

  * ``platform-versions.yaml``        -- the declared version set
  * ``src/platform-releases/.fetch-manifest.json`` -- the fetch manifest
    (per-target SHAs under ``targets``; the converter fingerprint is metadata
    the guard neither validates nor flags) written by ``make fetch``
  * ``src/platform-releases/<rev>/`` -- the generated per-version doc trees
    (the stable version's tree included), keyed by full git branch names.
    ``src/platform/`` is a HUMAN-maintained tree the guard does not look at.
  * ``src/_static/platform-versions.js`` -- the version switcher's generated
    data file (also written by ``make fetch``)

and fails loudly -- one named diagnostic per violation plus a ``run make fetch``
hint -- whenever the generated tree is missing or out of sync with the declared
version set. The point: a forgotten ``make fetch`` can never silently produce a
deployable-but-broken site, because the build refuses to start.

Bypass: ``SKIP_PLATFORM_CHECK=1`` skips the check locally with a LOUD stderr
warning -- but NEVER in CI. When the ``CI`` environment variable is truthy
(GitHub Actions, GitLab CI, ... set ``CI=true``) the check ALWAYS runs, so a
stale tree can never ship through CI even if someone exported the escape hatch.
"""

import os
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

import structlog

from tools.fetch_platform_docs import (
    PlatformConfig,
    load_config,
    load_manifest,
    stable_branch,
)

log = structlog.get_logger()

# Shared with the fetch tool so the guard checks the exact file ``make fetch``
# writes (and nothing else).
_MANIFEST_FILENAME = ".fetch-manifest.json"

# Escape hatch + CI override environment variables.
_SKIP_ENV = "SKIP_PLATFORM_CHECK"
_CI_ENV = "CI"

# Values treated as "yes" (case-insensitive). Everything else (incl. "0", "",
# "false", unset) is "no" -- predictable, no magic truthiness.
_TRUTHY = frozenset({"1", "true", "yes", "on"})


def is_truthy(value: str | None) -> bool:
    """Return True only for an explicit yes-value (``1``/``true``/``yes``/``on``).

    Anything else -- ``None``, empty string, ``0``, ``false`` -- is False. This
    matches how CI runners set ``CI=true`` and how the escape hatch is meant to
    be used (``SKIP_PLATFORM_CHECK=1``), without the surprising truthiness of a
    bare ``SKIP_PLATFORM_CHECK=`` (empty) being treated as set.
    """
    return bool(value) and value.strip().lower() in _TRUTHY


@dataclass(slots=True, frozen=True)
class Violation:
    """One consistency problem found by the guard.

    ``code`` is a stable, grep-friendly machine identifier
    (``target-dir-missing``); ``message`` is the human diagnostic that names the
    exact path/target; ``target`` is the affected target name (``None`` for
    tree-/manifest-level problems that are not tied to one version).
    """

    code: str
    target: str | None
    message: str


def expected_targets(cfg: PlatformConfig) -> list[str]:
    """Ordered, de-duplicated ARCHIVED targets the fetched tree MUST contain.

    Targets are the archived versions' full git branch names (``rev``): the
    on-disk layout is keyed by branch names -- each archived version lives at
    ``platform-releases/<rev>/`` -- mirroring the fetch manifest keys. (The
    stable version's tree is checked separately via its index page.) A
    pathological config that lists the same branch twice would otherwise
    demand two trees for one target, so duplicates are collapsed preserving
    first-seen order.
    """
    names = [e.rev for e in cfg.archived]
    seen: set[str] = set()
    unique: list[str] = []
    for name in names:
        if name not in seen:
            seen.add(name)
            unique.append(name)
    return unique


def has_files(path: Path) -> bool:
    """Return True if *path* contains at least one regular file anywhere below it.

    ``make fetch`` always writes Markdown + assets into each target dir, so a
    target with no file at all is a broken fetch (empty extraction, interrupted
    run). A directory holding only empty subdirectories counts as empty.
    """
    return any(p.is_file() for p in path.rglob("*"))


def check_platform(config_path: Path, output: Path) -> list[Violation]:
    """Return every consistency violation between the config, manifest and dirs.

    Pure-local: reads files only -- never the network, never git. An empty list
    means the fetched tree exactly matches the declared version set and is safe
    to build from.

    *output* is the docs source root (``src``): every version tree -- the
    stable one included -- lives at ``output/platform-releases/<rev>/``
    (with the manifest at
    ``output/platform-releases/.fetch-manifest.json``), exactly where
    :func:`tools.fetch_platform_docs.run_fetch` writes them -- which also
    emits the version switcher data file at
    ``output/_static/platform-versions.js`` (checked here as well).
    """
    cfg = load_config(config_path)
    wanted = expected_targets(cfg)
    releases_dir = output / "platform-releases"
    log.info(
        "check-platform-start",
        config=str(config_path),
        releases_dir=str(releases_dir),
        wanted_targets=wanted,
    )

    violations: list[Violation] = []

    # The whole generated tree is gone (fresh checkout, `make clean`, never
    # fetched). Nothing else is meaningfully checkable -- report and stop.
    if not releases_dir.is_dir():
        violations.append(
            Violation(
                "releases-dir-missing",
                None,
                f"platform release tree missing: {releases_dir} does not exist",
            )
        )
        log.warning("check-platform-done", violations=len(violations), ok=False)
        return violations

    # The stable version's tree must carry its index page at
    # platform-releases/<stable-branch>/index.md -- the branch name is derived
    # from the declared ver, and an index elsewhere (e.g. a leftover short-ver
    # platform-releases/25.05/ layout) is a stale tree, not a valid one.
    stable_index = releases_dir / stable_branch(cfg.stable) / "index.md"
    if not stable_index.is_file():
        violations.append(
            Violation(
                "stable-index-missing",
                None,
                f"stable platform index missing: {stable_index} not fetched",
            )
        )

    # The version switcher's data file is a fetch artifact, too: the built
    # versioned pages reference it, so a missing file would deploy a site
    # whose version flyout cannot work (empty data, broken fallback links).
    switcher_data = output / "_static" / "platform-versions.js"
    if not switcher_data.is_file():
        violations.append(
            Violation(
                "switcher-data-missing",
                None,
                f"version switcher data missing: {switcher_data} not generated",
            )
        )

    manifest_path = releases_dir / _MANIFEST_FILENAME
    has_manifest = manifest_path.is_file()
    # Manifest consumer: only the per-branch SHA targets matter here. The
    # converter fingerprint is fetch-boundary metadata -- a stale fingerprint
    # self-heals on the next ``make fetch`` and never makes the tree
    # unbuildable -- so it is neither validated nor flagged as an orphan key.
    targets: dict[str, str] = load_manifest(output)["targets"] if has_manifest else {}
    if not has_manifest:
        violations.append(
            Violation(
                "manifest-missing",
                None,
                f"fetch manifest missing: {manifest_path} does not exist",
            )
        )

    # Per declared archived version: the dir must exist, be non-empty, and (if
    # a manifest exists) have a manifest entry keyed by the git branch name.
    # The manifest-entry check is skipped when the manifest itself is absent to
    # avoid N redundant "no entry" diagnostics for a single root cause ("you
    # never fetched").
    for entry in cfg.archived:
        tgt_dir = output / "platform-releases" / entry.rev
        if not tgt_dir.is_dir():
            violations.append(
                Violation(
                    "target-dir-missing",
                    entry.rev,
                    f"target dir missing: {tgt_dir} not fetched",
                )
            )
        elif not has_files(tgt_dir):
            violations.append(
                Violation(
                    "target-dir-empty",
                    entry.rev,
                    f"target dir empty: {tgt_dir} has no files",
                )
            )
        if has_manifest and entry.rev not in targets:
            violations.append(
                Violation(
                    "manifest-entry-missing",
                    entry.rev,
                    f"manifest has no entry for branch {entry.rev!r}",
                )
            )

    # Orphan manifest keys: a branch recorded as fetched that the config no
    # longer declares. `make fetch` prunes these, so their presence means the
    # tree was hand-edited or the manifest is stale relative to the config.
    valid_branches = {stable_branch(cfg.stable)} | {e.rev for e in cfg.archived}
    if has_manifest:
        for key in sorted(k for k in targets if k not in valid_branches):
            violations.append(
                Violation(
                    "orphan-manifest-key",
                    key,
                    f"manifest key {key!r} is not declared in {config_path.name}",
                )
            )

    if violations:
        log.warning("check-platform-done", violations=len(violations), ok=False)
    else:
        log.info("check-platform-done", violations=0, ok=True)
    return violations


# Minimum log level for the CLI (matches logging.INFO; the int literal keeps the
# guard free of an ``import logging`` per the project's structlog-only rule).
_INFO_LEVEL = 20


def _configure_logging() -> None:
    """Render human-readable diagnostics to stderr.

    ``make`` surfaces a failing prerequisite's stderr verbatim, so the guard's
    structured events ARE the user-facing diagnostics. Filtered to INFO+ so a
    successful check is quiet (the shared fetch helpers emit DEBUG that would
    otherwise spam every build). Configured here (not at import time) so
    importing the module in tests stays side-effect-free; tests that inspect
    structured events use ``structlog.testing.capture_logs``, which swaps and
    restores this config and captures every level regardless of the filter.
    """
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.add_log_level,
            structlog.dev.ConsoleRenderer(colors=False),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(_INFO_LEVEL),
        # Diagnostics belong on stderr: `make` surfaces a failing prerequisite's
        # stderr verbatim, while stdout must stay clean for Sphinx. Resolved at
        # call time (inside main) so pytest's capsys captures it.
        logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
    )


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry: ``python -m tools.check_platform <config> <src-dir>``.

    Exit codes: ``0`` (consistent, or bypassed via SKIP outside CI), ``1``
    (inconsistent), ``2`` (bad invocation).
    """
    _configure_logging()
    args = list(sys.argv[1:] if argv is None else argv)
    if len(args) != 2:
        log.warning(
            "check-platform-usage",
            args=args,
            usage="python -m tools.check_platform <platform-versions.yaml> <src-dir>",
        )
        return 2

    config_path, output = Path(args[0]), Path(args[1])

    in_ci = is_truthy(os.environ.get(_CI_ENV))
    skip = is_truthy(os.environ.get(_SKIP_ENV))

    # Local escape hatch -- but CI is never allowed to bypass: a stale tree must
    # never ship through CI, regardless of who set SKIP_PLATFORM_CHECK.
    if skip and not in_ci:
        log.warning(
            "check-platform-skipped",
            reason=f"{_SKIP_ENV}=1",
            warning=(
                "platform consistency NOT verified -- a stale or missing "
                "src/platform-releases/ tree will not be caught"
            ),
            hint="run `make fetch` if unsure",
        )
        return 0

    violations = check_platform(config_path, output)
    if not violations:
        log.info(
            "check-platform-ok",
            skipped=skip,
            ci=in_ci,
            hint="platform tree is consistent with the declared version set",
        )
        return 0

    for v in violations:
        log.error(
            "check-platform-violation",
            code=v.code,
            target=v.target,
            message=v.message,
        )
    log.error(
        "check-platform-failed",
        violations=len(violations),
        ci=in_ci,
        hint=f"run `make fetch` to regenerate src/platform-releases/ from {config_path.name}",
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
