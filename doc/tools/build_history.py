"""Build the living VCS history of the documentation (``make history``).

For a revset of hg revisions (default ``1952::tip`` -- the Zensical era),
this tool builds the English manual of EACH revision into its own parallel
directory ``_history/<rev>/`` (served as ``/v/<rev>/`` by
``deploy/history.nix``), plus the shared landing page
(``_history/index.html``), the overlay assets and the manifest
(``_history/manifest.json``) that drives both.

Per revision (all of it inside ONE injectable build callable -- the seams
are chosen so the whole contract runs without network, hg or zensical):

1. ``hg archive`` the repository at the revision's node into a staging dir
   ``_history/<rev>.tmp/work``;
2. bootstrap THAT revision's own build toolchain (its appenv pins the
   historic builder -- Sphinx era up to rev 1951, Zensical from 1952 on)
   and run ``make fetch`` against its historic ``platform-versions.yaml``
   pins. The git fetch cache is SHARED with the current repo (symlink
   ``.fetch-cache``) and serialized behind a lock, so parallel revision
   builds never race on it. A failed historic fetch takes the documented
   fallback: build against TODAY's ``src/platform`` tree with
   ``SKIP_PLATFORM_CHECK=1`` and record ``content: "current"`` in the
   manifest (a successful historic fetch records ``content: "historic"``).
3. build the English manual (``make html-en``; Sphinx-era revisions only
   have ``make html``) -- both eras emit the site at ``work/_build/en``;
4. move the built site up to the staging root and drop the work tree;
5. ``build_history`` renames staging to ``_history/<rev>/`` atomically
   (``.tmp`` + rename -- a revision directory only ever appears complete)
   and injects the overlay tags into every built ``*.html``.

A failed revision build is DATA, not an abort: the manifest entry records
``status: "failed"`` with a log excerpt (rendered red on the landing page),
the staging dir is discarded and the run continues. Completed revisions
(existing ``_history/<rev>/``) are skipped, so runs are incremental and
resumable; ``make history REVS=<rev>`` builds exactly that revision.

Manifest schema (pinned by ``tests/test_build_history.py``, consumed by
the landing page and the overlay)::

    {"revisions": [entry, ...]}   # ascending by rev
    entry = {rev, hash, date, branch, subject,
             status, content, duration, log_excerpt}
"""

import html
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import structlog

log = structlog.get_logger()

# Overlay tags injected before </body>: addressed via the served /v/ prefix
# so they resolve at any page depth. overlay.js loads its pure-logic module
# (history-urls.js) dynamically -- the injection stays exactly one <link> +
# one <script> per page.
_OVERLAY_LINK = '<link rel="stylesheet" href="/v/overlay.css">'
_OVERLAY_SCRIPT = '<script defer src="/v/overlay.js"></script>'

# Manifest filename inside the history root (served as /v/manifest.json).
MANIFEST_FILENAME = "manifest.json"

# Landing page of the history browser (served as /v/ -- nginx index).
LANDING_FILENAME = "index.html"

# Committed overlay assets (tools/history_assets/) copied into the history
# root by copy_overlay_assets().
ASSET_DIR = Path(__file__).resolve().parent / "history_assets"
OVERLAY_ASSETS = ("overlay.js", "overlay.css", "history-urls.js")

# hg log template for revset resolution: unit-separator delimited fields,
# record-separator delimited records (subjects are single-line via
# {desc|firstline}, so no field can contain a separator).
_HG_TEMPLATE = "{rev}\x1f{node}\x1f{date|shortdate}\x1f{branch}\x1f{desc|firstline}\x1e"

# Default revset: the Zensical era (rev 1952 switched the Makefile from
# Sphinx to Zensical). Older revisions build via `make history REVS=<revset>`
# -- their per-revision appenv bootstraps the historic Sphinx toolchain.
DEFAULT_REVSET = "1952::tip"

# Era-specific build target: Zensical-era Makefiles have html-en; the Sphinx
# era (<= 1951) only has html. Both eras emit the site at _build/en.
_HTML_EN_TARGET_RE = re.compile(r"^html-en:", re.MULTILINE)
_SITE_CANDIDATES = ("_build/en", "_build/html")

# Today's fetched platform trees used by the documented fetch fallback
# (fetch failed -> SKIP_PLATFORM_CHECK=1 with the current src/). Everything
# the build reads out of src/ after a successful fetch, mirrored verbatim.
_FALLBACK_TREES = (
    "platform",
    "components",
    "platform-releases",
    "_static/platform-versions.js",
)

# Tail size (chars) of the captured build transcript recorded as
# log_excerpt for failed revisions.
_LOG_EXCERPT_CHARS = 4000


@dataclass(slots=True)
class Revision:
    """One hg revision of the docs repo, as resolved by ``hg log``.

    ``rev`` is the LOCAL revision number (string) -- it doubles as the
    directory name under ``_history/`` and the URL segment under ``/v/``.
    """

    rev: str
    hash: str
    date: str
    branch: str
    subject: str


@dataclass(slots=True)
class BuildResult:
    """Outcome of one revision build (returned by the build callable).

    ``status``: "ok" | "failed". ``content``: "historic" (built against the
    revision's own platform-versions.yaml pins) | "current" (documented
    fallback: historic fetch failed, built against today's fetched tree).
    ``log_excerpt``: "" for ok; tail of the build log for failed revisions.
    """

    status: str
    content: str
    duration: float
    log_excerpt: str


# --- overlay injection --------------------------------------------------------


def inject_overlay(page_html: str) -> str:
    """Insert the overlay <link>/<script> tags before ``</body>`` -- idempotent.

    Exactly one stylesheet link (/v/overlay.css) and one script tag
    (/v/overlay.js) per page; HTML that already carries both tags passes
    through unchanged (post-build injection runs on every history run, a
    non-idempotent injector would stack tags on rebuilds). Pages without a
    ``</body>`` get the tags appended -- still exactly one of each.
    """
    need_link = _OVERLAY_LINK not in page_html
    need_script = _OVERLAY_SCRIPT not in page_html
    if not need_link and not need_script:
        log.debug("overlay-already-injected")
        return page_html
    tags = (
        f"{_OVERLAY_LINK}{_OVERLAY_SCRIPT}"
        if need_link and need_script
        else _OVERLAY_LINK
        if need_link
        else _OVERLAY_SCRIPT
    )
    at = page_html.rfind("</body>")
    injected = page_html + tags if at == -1 else page_html[:at] + tags + page_html[at:]
    log.debug("overlay-injected", added_link=need_link, added_script=need_script)
    return injected


def inject_overlay_tree(root: Path) -> int:
    """Inject the overlay tags into every ``*.html`` under *root*.

    Returns the number of pages touched. Runs over the FINAL revision tree
    after its atomic rename, so a half-injected tree is never served.
    """
    pages = sorted(root.rglob("*.html"))
    for page in pages:
        page.write_text(
            inject_overlay(page.read_text(encoding="utf-8")), encoding="utf-8"
        )
    log.info("overlay-injected-tree", root=str(root), pages=len(pages))
    return len(pages)


# --- manifest -----------------------------------------------------------------


def staging_dir_for(history_root: Path, rev: str) -> Path:
    """Staging dir of a revision inside the history root (``<rev>.tmp``).

    The ``.tmp`` suffix marks the dir as incomplete on disk; the final
    placement is an atomic same-filesystem rename to ``<history_root>/<rev>``.
    """
    return history_root / f"{rev}.tmp"


def load_manifest(history_root: Path) -> dict:
    """Read ``<history_root>/manifest.json``; ``{"revisions": []}`` if absent.

    A malformed manifest file crashes loudly (json error propagates) -- a
    corrupt manifest must never silently reset the history index.
    """
    path = history_root / MANIFEST_FILENAME
    if not path.is_file():
        return {"revisions": []}
    manifest = json.loads(path.read_text(encoding="utf-8"))
    log.info(
        "history-manifest-loaded",
        path=str(path),
        revisions=len(manifest.get("revisions", [])),
    )
    return manifest


def write_manifest(history_root: Path, manifest: dict) -> Path:
    """Persist the manifest atomically (write ``.tmp``, then rename)."""
    path = history_root / MANIFEST_FILENAME
    tmp = history_root / f"{MANIFEST_FILENAME}.tmp"
    tmp.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    log.debug(
        "history-manifest-written", path=str(path), revisions=len(manifest["revisions"])
    )
    return path


def _entry(revision: Revision, result: BuildResult) -> dict:
    """Manifest entry for one revision -- exactly the pinned keys."""
    return {
        "rev": revision.rev,
        "hash": revision.hash,
        "date": revision.date,
        "branch": revision.branch,
        "subject": revision.subject,
        "status": result.status,
        "content": result.content,
        "duration": result.duration,
        "log_excerpt": result.log_excerpt,
    }


def _orphan_entry(revision: Revision) -> dict:
    """Entry for a built revision the manifest has no record of.

    Only reachable when ``_history/<rev>/`` exists but manifest.json carries
    no entry for it (manifest lost between two runs): the build is NOT rerun
    (resumability), so the entry is synthesized from the hg log data with an
    explicit ``content: "unknown"`` flag -- provenance is honestly unknown,
    the landing page renders the row greyed out instead of pretending.
    """
    log.warning(
        "history-entry-orphaned",
        rev=revision.rev,
        reason="revision dir exists but manifest.json has no entry",
        content="unknown",
    )
    return {
        "rev": revision.rev,
        "hash": revision.hash,
        "date": revision.date,
        "branch": revision.branch,
        "subject": revision.subject,
        "status": "ok",
        "content": "unknown",
        "duration": 0.0,
        "log_excerpt": "",
    }


# --- the orchestrator (contract seams) ----------------------------------------


def build_history(
    history_root: Path,
    revisions: Sequence[Revision],
    build: Callable[[Revision, Path], BuildResult],
    *,
    jobs: int = 1,
) -> dict:
    """Build every *revision* into ``<history_root>/<rev>/``, return the manifest.

    Per revision, ascending by rev:

    * SKIP when ``<history_root>/<rev>/`` already exists -- the build
      callable must not run again; the existing manifest entry is preserved
      verbatim (resumability of interrupted runs).
    * Otherwise the build callable receives a STAGING dir inside the history
      root (``<rev>.tmp`` -- never the final path). On
      ``BuildResult(status="ok")`` the staging dir is renamed atomically to
      ``<history_root>/<rev>/`` and the overlay tags are injected into every
      built ``*.html`` of the final tree. On ``status="failed"`` the staging
      dir is discarded and the run CONTINUES -- a failed revision is data
      (red landing-page entry with log excerpt), not an abort.

    ``manifest.json`` is (re-)written after every completed revision, so an
    interrupted run leaves it consistent with the built directories. The
    returned manifest ``{"revisions": [entry, ...]}`` is ascending by rev.

    ``jobs > 1`` runs the build callables of pending revisions through a
    thread pool (the production builder serializes its fetch phase behind a
    lock). An unexpected EXCEPTION from a build callable is recorded as a
    failed revision (traceback tail as log_excerpt) and the run continues --
    the failure is loudly logged and lands in the manifest, never hidden.
    """
    history_root.mkdir(parents=True, exist_ok=True)
    ordered = sorted(revisions, key=lambda r: int(r.rev))
    previous = {e["rev"]: e for e in load_manifest(history_root).get("revisions", [])}
    entries: dict[str, dict] = {}
    pending: list[Revision] = []

    for revision in ordered:
        if (history_root / revision.rev).exists():
            entries[revision.rev] = previous.get(revision.rev) or _orphan_entry(
                revision
            )
            log.info(
                "history-revision-skipped",
                rev=revision.rev,
                reason="already built",
                has_manifest_entry=revision.rev in previous,
            )
        else:
            pending.append(revision)

    def persist() -> dict:
        manifest = {"revisions": [entries[r.rev] for r in ordered if r.rev in entries]}
        write_manifest(history_root, manifest)
        return manifest

    def finalize(revision: Revision, result: BuildResult) -> None:
        staging = staging_dir_for(history_root, revision.rev)
        if result.status == "ok":
            staging.rename(history_root / revision.rev)
            inject_overlay_tree(history_root / revision.rev)
        else:
            if staging.exists():
                shutil.rmtree(staging)
            log.warning(
                "history-revision-failed",
                rev=revision.rev,
                content=result.content,
                duration=result.duration,
                log_excerpt=result.log_excerpt[-500:],
            )
        entries[revision.rev] = _entry(revision, result)
        persist()

    if not pending:
        manifest = persist()
        log.info(
            "history-run-finished",
            total=len(ordered),
            built=0,
            skipped=len(ordered),
            failed=0,
        )
        return manifest

    def run_one(revision: Revision) -> BuildResult:
        try:
            return build(revision, staging_dir_for(history_root, revision.rev))
        except Exception as exc:
            # Safety net for unexpected exceptions (the production builder
            # reports build failures as BuildResult itself): the failure is
            # DATA per contract -- logged with full context, recorded in
            # the manifest (red landing-page entry), run continues.
            log.exception(
                "history-revision-crashed",
                rev=revision.rev,
                hash=revision.hash[:12],
                error=repr(exc),
            )
            return BuildResult(
                status="failed",
                content="current",
                duration=0.0,
                log_excerpt=f"unexpected error: {exc!r}",
            )

    built = failed = 0

    def settle(revision: Revision, result: BuildResult) -> None:
        nonlocal built, failed
        finalize(revision, result)
        if result.status == "ok":
            built += 1
        else:
            failed += 1

    if jobs <= 1:
        # STRICTLY sequential: each revision's manifest persist completes
        # before the next revision's build starts -- an interrupted run
        # leaves manifest.json consistent with the built directories.
        for revision in pending:
            settle(revision, run_one(revision))
    else:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = [pool.submit(run_one, revision) for revision in pending]
            for revision, future in zip(pending, futures, strict=True):
                settle(revision, future.result())

    manifest = persist()
    log.info(
        "history-run-finished",
        total=len(ordered),
        built=built,
        skipped=len(ordered) - len(pending),
        failed=failed,
        history_root=str(history_root),
    )
    return manifest


# --- revset resolution --------------------------------------------------------


def _run_hg(args: Sequence[str], cwd: Path) -> str:
    """Run an hg command, return stdout; failures crash loudly with output."""
    cmd = ["hg", *args]
    proc = subprocess.run(
        cmd, cwd=str(cwd), capture_output=True, text=True, check=False
    )
    if proc.returncode != 0:
        log.error(
            "hg-command-failed",
            cmd=cmd,
            cwd=str(cwd),
            returncode=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
        )
        raise RuntimeError(
            f"hg failed (exit {proc.returncode}): {' '.join(cmd)}\n"
            f"--- stdout ---\n{proc.stdout}--- stderr ---\n{proc.stderr}"
        )
    return proc.stdout


def resolve_revisions(
    repo_root: Path, revset: str, *, run_fn: Callable[[list[str], Path], str] = _run_hg
) -> list[Revision]:
    """Resolve *revset* via ``hg log`` into Revision objects, ascending by rev.

    ``run_fn(["log", ...], cwd)`` is injectable for testing; the production
    runner shells out to hg in *repo_root*.
    """
    out = run_fn(["log", "--rev", revset, "--template", _HG_TEMPLATE], repo_root)
    revisions: list[Revision] = []
    for record in out.split("\x1e"):
        if not record.strip():
            continue
        rev, node, date, branch, subject = record.strip("\n").split("\x1f")
        revisions.append(
            Revision(rev=rev, hash=node, date=date, branch=branch, subject=subject)
        )
    revisions.sort(key=lambda r: int(r.rev))
    log.info(
        "history-revisions-resolved",
        revset=revset,
        count=len(revisions),
        first=revisions[0].rev if revisions else None,
        last=revisions[-1].rev if revisions else None,
    )
    return revisions


# --- production build callable ------------------------------------------------


class _StepFailure(RuntimeError):
    """One revision-build step failed; message lands in the manifest entry."""


def _tail(text: str, limit: int = _LOG_EXCERPT_CHARS) -> str:
    """Last *limit* chars of *text* -- the log excerpt for failed builds."""
    return text[-limit:].lstrip()


class RevisionBuilder:
    """Production ``build`` callable: hg archive -> make fetch -> make html.

    All heavy work lives in ``__call__`` so :func:`build_history` stays the
    orchestrator: archiving the repo at the revision's node, bootstrapping
    THAT revision's toolchain (its own appenv/pyproject/uv.lock -- historic
    builder era), fetching against its historic pins (shared, lock-serialized
    ``.fetch-cache`` symlink) and building the English site into the staging
    dir. Subprocess failures raise :class:`_StepFailure` carrying the output
    tail; ``__call__`` converts them into ``BuildResult(status="failed")`` --
    a failed revision is manifest data, the run continues.

    ``run_fn(cmd, cwd, env)`` is injectable for testing (same seam as
    ``tools.fetch_platform_docs.ensure_repo``).
    """

    def __init__(
        self,
        repo_root: Path,
        *,
        run_fn: Callable[
            [list[str], Path, dict[str, str] | None], subprocess.CompletedProcess
        ]
        | None = None,
    ) -> None:
        self.repo_root = repo_root
        self._fetch_lock = threading.Lock()
        self._run_fn = run_fn or self._default_run

    @staticmethod
    def _default_run(
        cmd: list[str], cwd: Path, env: dict[str, str] | None
    ) -> subprocess.CompletedProcess:
        proc = subprocess.run(
            cmd, cwd=str(cwd), capture_output=True, text=True, env=env, check=False
        )
        log.info(
            "history-subprocess",
            cmd=cmd,
            cwd=str(cwd),
            returncode=proc.returncode,
            stdout_tail=proc.stdout[-400:],
            stderr_tail=proc.stderr[-400:],
        )
        return proc

    def _run(
        self,
        cmd: list[str],
        cwd: Path,
        transcript: list[str],
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess:
        proc = self._run_fn(cmd, cwd, env)
        transcript.append(f"$ {' '.join(cmd)}\n{proc.stdout}{proc.stderr}")
        return proc

    def __call__(self, revision: Revision, staging: Path) -> BuildResult:
        started = time.monotonic()
        work = staging / "work"
        transcript: list[str] = []
        content = "current"
        log.info(
            "history-build-started",
            rev=revision.rev,
            hash=revision.hash[:12],
            subject=revision.subject,
            staging=str(staging),
        )
        try:
            if staging.exists():
                # Stale staging of an interrupted run -- the .tmp dir is
                # never served, safe (and required) to start clean.
                log.info(
                    "history-staging-cleared", rev=revision.rev, staging=str(staging)
                )
                shutil.rmtree(staging)
            staging.mkdir(parents=True, exist_ok=True)
            self._archive(revision, work)
            content = self._fetch(revision, work, transcript)
            self._build_site(revision, work, content, transcript)
            _move_site(work, staging)
        except _StepFailure as exc:
            if work.exists():
                shutil.rmtree(work, ignore_errors=False)
            duration = round(time.monotonic() - started, 1)
            excerpt = _tail("".join(transcript) + f"\n{exc}")
            log.error(
                "history-build-failed",
                rev=revision.rev,
                hash=revision.hash[:12],
                duration=duration,
                content=content,
                error=str(exc)[:500],
            )
            return BuildResult(
                status="failed", content=content, duration=duration, log_excerpt=excerpt
            )
        duration = round(time.monotonic() - started, 1)
        log.info(
            "history-build-finished",
            rev=revision.rev,
            duration=duration,
            content=content,
        )
        return BuildResult(
            status="ok", content=content, duration=duration, log_excerpt=""
        )

    def _archive(self, revision: Revision, work: Path) -> None:
        """``hg archive`` the repo at the revision's node into *work*."""
        if work.exists():
            shutil.rmtree(work)
        with self._fetch_lock:
            proc = self._run(
                ["hg", "archive", "--rev", revision.hash, str(work.resolve())],
                self.repo_root,
                [],
            )
        if proc.returncode != 0:
            raise _StepFailure(
                f"hg archive failed for rev {revision.rev} (exit {proc.returncode})"
            )

    def _fetch(self, revision: Revision, work: Path, transcript: list[str]) -> str:
        """Historic ``make fetch``; documented fallback on failure.

        Returns the content flag: "historic" (fetched against the revision's
        own platform-versions.yaml pins) or "current" (fetch failed -> build
        against today's src/platform with SKIP_PLATFORM_CHECK=1).
        """
        shared_cache = self.repo_root / ".fetch-cache"
        if shared_cache.is_dir() and not (work / ".fetch-cache").exists():
            (work / ".fetch-cache").symlink_to(shared_cache.resolve())
            log.debug(
                "history-fetch-cache-shared",
                rev=revision.rev,
                link=str(work / ".fetch-cache"),
                target=str(shared_cache.resolve()),
            )
        with self._fetch_lock:
            proc = self._run(["make", "fetch"], work, transcript)
        if proc.returncode == 0:
            log.info("history-fetch-historic", rev=revision.rev)
            return "historic"
        log.warning(
            "history-fetch-failed-fallback",
            rev=revision.rev,
            returncode=proc.returncode,
            fallback="SKIP_PLATFORM_CHECK=1 with today's src/ (content=current)",
        )
        self._copy_current_platform_trees(revision, work)
        return "current"

    def _copy_current_platform_trees(self, revision: Revision, work: Path) -> None:
        """Mirror today's fetched platform trees into the archived *work* tree."""
        for rel in _FALLBACK_TREES:
            src = self.repo_root / "src" / rel
            if not src.exists():
                raise _StepFailure(
                    f"historic fetch failed for rev {revision.rev} and the "
                    f"documented fallback is unavailable: {src} missing "
                    "(run `make fetch` in the current repo first)"
                )
            dest = work / "src" / rel
            if dest.is_dir():
                shutil.rmtree(dest)
            elif dest.exists():
                dest.unlink()
            (dest.parent).mkdir(parents=True, exist_ok=True)
            shutil.copytree(src, dest) if src.is_dir() else shutil.copyfile(src, dest)

    def _build_site(
        self, revision: Revision, work: Path, content: str, transcript: list[str]
    ) -> None:
        """Build the English manual with the revision's own Makefile."""
        makefile = work / "Makefile"
        if not makefile.is_file():
            raise _StepFailure(f"rev {revision.rev}: no Makefile in the archived tree")
        target = (
            "html-en"
            if _HTML_EN_TARGET_RE.search(makefile.read_text(encoding="utf-8"))
            else "html"
        )
        env = dict(os.environ)
        if content == "current":
            env["SKIP_PLATFORM_CHECK"] = "1"
        proc = self._run(["make", target], work, transcript, env=env)
        if proc.returncode != 0:
            raise _StepFailure(
                f"make {target} failed for rev {revision.rev} (exit {proc.returncode})"
            )


def _move_site(work: Path, staging: Path) -> None:
    """Move the built site from ``work/_build/<dir>`` up to the staging root.

    Both builder eras emit the English site at ``_build/en`` (Sphinx
    EN_BUILDDIR = _build/en, Zensical site_dir = _build/en); ``_build/html``
    is kept as a candidate for pre-1951 trees that deviated. The work tree
    (archived sources, .appenv venv) is removed afterwards -- only the site
    gets renamed into _history/<rev>/.
    """
    site = next(
        (
            work / candidate
            for candidate in _SITE_CANDIDATES
            if (work / candidate / "index.html").is_file()
        ),
        None,
    )
    if site is None:
        tried = ", ".join(_SITE_CANDIDATES)
        raise _StepFailure(
            f"no built site found under {work} (tried {tried}) -- build produced no index.html"
        )
    for entry in sorted(site.iterdir()):
        shutil.move(str(entry), str(staging / entry.name))
    shutil.rmtree(work)
    log.info("history-site-placed", staging=str(staging), site=str(site))


# --- landing page + assets ------------------------------------------------------


def build_landing_page(manifest: dict) -> str:
    """Render the history landing page (timeline, newest first) as HTML.

    Failed revisions render red with their log excerpt; ``content: current``
    rows carry the fallback note (built against today's sources) and
    ``content: unknown`` rows (orphaned dirs, :func:`_orphan_entry`) render
    greyed out with a provenance note instead of pretending. The page is
    self-contained -- the historic builds' era styling must not leak into
    the landing (and vice versa).
    """
    rows = []
    for entry in reversed(manifest.get("revisions", [])):
        failed = entry.get("status") != "ok"
        fallback = entry.get("content") == "current"
        unknown = entry.get("content") == "unknown"
        css_class = (
            "failed"
            if failed
            else "current"
            if fallback
            else "unknown"
            if unknown
            else "ok"
        )
        note = (
            '<span class="flag">content: current (historic fetch failed, '
            "built against today's sources)</span>"
            if fallback
            else '<span class="flag">content: unknown (manifest entry '
            "lost -- provenance unknown)</span>"
            if unknown
            else ""
        )
        excerpt = (
            f'<pre class="excerpt">{html.escape(entry.get("log_excerpt", ""))}</pre>'
            if failed
            else ""
        )
        subject = html.escape(entry.get("subject", ""))
        link = (
            f'<a href="/v/{entry["rev"]}/">{entry["rev"]}</a>'
            if not failed
            else html.escape(str(entry["rev"]))
        )
        rows.append(
            f'<tr class="{css_class}">'
            f"<td>{link}</td>"
            f"<td>{html.escape(str(entry.get('date', '')))}</td>"
            f"<td>{html.escape(str(entry.get('branch', '')))}</td>"
            f"<td>{subject}{note}</td>"
            f"<td>{html.escape(str(entry.get('status', '')))}"
            f" ({entry.get('duration', 0)}s)</td>"
            f"</tr>{excerpt}"
        )
    return (
        "<!DOCTYPE html>\n"
        '<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
        "<title>Documentation history</title>\n"
        "<style>\n"
        "body { font: 15px/1.5 system-ui, sans-serif; margin: 2rem auto; max-width: 60rem; }\n"
        "h1 { font-size: 1.5rem; }\n"
        "table { border-collapse: collapse; width: 100%; }\n"
        "th, td { text-align: left; padding: 0.35rem 0.6rem; border-bottom: 1px solid #ddd; vertical-align: top; }\n"
        "tr.failed td { color: #b3261e; background: #fdeceb; }\n"
        "tr.current .flag { display: block; font-size: 0.85em; color: #8a6d00; }\n"
        "tr.unknown td { color: #5f6368; }\n"
        "tr.unknown .flag { display: block; font-size: 0.85em; color: #5f6368; }\n"
        "pre.excerpt { margin: 0 0 0.6rem; padding: 0.4rem 0.6rem; background: #fdeceb; "
        "color: #b3261e; white-space: pre-wrap; font-size: 0.85em; }\n"
        "</style>\n</head>\n<body>\n"
        "<h1>Documentation history</h1>\n"
        "<p>Every revision of the manual, built from its own hg revision and "
        "served under <code>/v/&lt;rev&gt;/</code>. Use the overlay bar on any "
        "history page to switch revisions or jump to the state of a given "
        "date.</p>\n"
        "<table>\n<thead>\n<tr><th>Rev</th><th>Date</th><th>Branch</th>"
        "<th>Subject</th><th>Status</th></tr>\n</thead>\n<tbody>\n"
        + "\n".join(rows)
        + "\n</tbody>\n</table>\n</body>\n</html>\n"
    )


def write_landing_page(history_root: Path, manifest: dict) -> Path:
    """Write ``<history_root>/index.html`` (with overlay) from *manifest*."""
    path = history_root / LANDING_FILENAME
    history_root.mkdir(parents=True, exist_ok=True)
    page = inject_overlay(build_landing_page(manifest))
    path.write_text(page, encoding="utf-8")
    log.info(
        "history-landing-written",
        path=str(path),
        revisions=len(manifest.get("revisions", [])),
    )
    return path


def copy_overlay_assets(history_root: Path) -> list[Path]:
    """Copy the committed overlay assets into the history root (as /v/*).

    Served at the /v/ prefix the injected tags address: /v/overlay.js,
    /v/overlay.css and /v/history-urls.js (loaded dynamically by overlay.js).
    """
    copied = []
    for name in OVERLAY_ASSETS:
        src = ASSET_DIR / name
        if not src.is_file():
            raise FileNotFoundError(
                f"overlay asset missing: {src} -- the committed tools/history_assets/ "
                "dir must ship overlay.js, overlay.css and history-urls.js"
            )
        dest = history_root / name
        history_root.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        copied.append(dest)
    log.info(
        "history-assets-copied", assets=[str(p) for p in copied], dest=str(history_root)
    )
    return copied


# --- CLI ------------------------------------------------------------------------


def _configure_logging() -> None:
    """Human-readable diagnostics on stderr (same setup as check_platform)."""
    structlog.configure(
        processors=[
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.add_log_level,
            structlog.dev.ConsoleRenderer(colors=False),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(20),  # INFO+
        logger_factory=structlog.PrintLoggerFactory(file=sys.stderr),
    )


_USAGE = (
    "python -m tools.build_history [--history-root DIR] [--revs REVSET] "
    "[--jobs N] [--repo-root DIR] [--index-only]"
)


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry behind ``make history`` / ``make history-index``.

    Exit codes: 0 (run finished -- failed revisions are manifest data, the
    landing page shows them red), 1 (nothing to build from / landing
    prerequisites missing), 2 (bad invocation).
    """
    _configure_logging()
    args = list(sys.argv[1:] if argv is None else argv)

    opts = {
        "--history-root": "_history",
        "--revs": DEFAULT_REVSET,
        "--jobs": "1",
        "--repo-root": ".",
    }
    index_only = False
    it = iter(args)
    for arg in it:
        if arg == "--index-only":
            index_only = True
        elif arg in opts:
            try:
                opts[arg] = next(it)
            except StopIteration:
                log.error(
                    "history-cli-usage", error=f"{arg} requires a value", usage=_USAGE
                )
                return 2
        else:
            log.error(
                "history-cli-usage", error=f"unknown argument {arg!r}", usage=_USAGE
            )
            return 2
    try:
        jobs = int(opts["--jobs"])
        if jobs < 1:
            raise ValueError
    except ValueError:
        log.error(
            "history-cli-usage",
            error=f"--jobs must be a positive integer, got {opts['--jobs']!r}",
        )
        return 2

    repo_root = Path(opts["--repo-root"]).resolve()
    history_root = Path(opts["--history-root"]).resolve()
    history_root.mkdir(parents=True, exist_ok=True)

    if index_only:
        manifest = load_manifest(history_root)
        if not manifest.get("revisions"):
            log.error(
                "history-index-impossible",
                reason="manifest.json carries no revisions (run `make history` first)",
                history_root=str(history_root),
            )
            return 1
        write_landing_page(history_root, manifest)
        copy_overlay_assets(history_root)
        return 0

    revisions = resolve_revisions(repo_root, opts["--revs"])
    if not revisions:
        log.error(
            "history-revset-empty",
            revset=opts["--revs"],
            hint="the revset matched no revision -- typo? (default: 1952::tip)",
        )
        return 1

    manifest = build_history(
        history_root, revisions, RevisionBuilder(repo_root), jobs=jobs
    )
    write_landing_page(history_root, manifest)
    copy_overlay_assets(history_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
