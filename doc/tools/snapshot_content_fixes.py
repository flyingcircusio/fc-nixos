"""Content fixes applied to placed version snapshots.

The new-docs version branches carry pre-fix content: dead split-era
link targets (``platform-releases/<branch>/...`` and
``../platform/<branch>/...``) plus old fetch-era sunsetting banners
with dead links. This table is the exact set of fixes already applied
to the integration line, applied to every placed snapshot so builds
stay link-clean without backporting first.

BACKPORT DEBT: as fixes land on the version branches the table
shrinks -- when every entry matches nothing, this module dies.
"""

from __future__ import annotations

import re
from pathlib import Path

# (old, new) pairs, applied verbatim to every *.md of a placed snapshot.
FIXES: list[tuple[str, str]] = [
    # platform-releases split-era targets (platform/ pages)
    (
        "[managed components](../../platform-releases/fc-26.05-production/index.md#nixos-components)",
        "managed components",
    ),
    (
        "../../platform-releases/fc-26.05-production/logrotate.md#nixos-logrotate",
        "logrotate.md#nixos-logrotate",
    ),
    (
        "../../platform-releases/fc-26.05-production/user_profile.md#nixos-user-package-management",
        "user-profile.md#nixos-user-package-management",
    ),
    (
        "../../platform-releases/fc-26.05-production/local.md#nixos-local",
        "local.md#nixos-local",
    ),
    (
        "../../platform-releases/fc-26.05-production/systemd.md#nixos-systemd-app-service-example",
        "#nixos-systemd-app-service-example",
    ),
    # split-era targets under ../platform/<branch>/ (components/ pages)
    (
        "../platform/fc-26.05-production/local.md#nixos-custom-modules",
        "../platform/local.md#nixos-custom-modules",
    ),
    (
        "../platform/fc-26.05-production/local.md#nixos-local",
        "../platform/local.md#nixos-local",
    ),
    (
        "../platform/fc-26.05-production/upgrade.md#nixos-upgrade",
        "../platform/upgrades-whats-new.md#nixos-upgrade",
    ),
    (
        "../platform/fc-26.05-production/images/http_platform.png",
        "../images/http_platform.png",
    ),
    (
        "../platform/fc-26.05-production/images/tcp_ingress.png",
        "../images/tcp_ingress.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-explore.png",
        "../images/statshost/loki-explore.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-datasource.png",
        "../images/statshost/loki-datasource.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-simple-query.png",
        "../images/statshost/loki-simple-query.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-simple-query-results.png",
        "../images/statshost/loki-simple-query-results.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-demo-dashboards.png",
        "../images/statshost/loki-demo-dashboards.png",
    ),
    (
        "../platform/fc-26.05-production/images/statshost/loki-basic-logging-dashboard.png",
        "../images/statshost/loki-basic-logging-dashboard.png",
    ),
    # wrong-depth refs (getting-started era)
    ("![](../images/vorteile250.png)", "![](../../images/vorteile250.png)"),
    (
        "../security/data-protection.md#entry-control",
        "../../security/data-protection.md#entry-control",
    ),
    (
        "../infrastructure/networking/connecting.md#connecting",
        "../networking/connecting.md#connecting",
    ),
    (
        "../platform/users/index.md#useraccounts",
        "../../platform/users/index.md#useraccounts",
    ),
    (
        "../platform/deployment/index.md#application-deployment",
        "../../platform/deployment/index.md#application-deployment",
    ),
    (
        "../infrastructure/networking/index.md#networking",
        "../networking/index.md#networking",
    ),
    (
        "../../getting-started/index.md#firststeps",
        "../../infrastructure/getting-started/index.md#firststeps",
    ),
    ("../reference/users/index.md", "../platform/users/index.md"),
    # mangled Sphinx/RST remnants
    (
        "`current NixOS platform documentation <nixos-platform-index>`",
        "current NixOS platform documentation",
    ),
    (
        "See <project:../../infrastructure/backup.md> for possible values.",
        "See [the backup documentation](../../infrastructure/backup.md) for possible values.",
    ),
    ("`documentation <nixos-slurm>`", "documentation"),
    (
        "`documentation on upgrades and changes <nixos-upgrade>`",
        "documentation on upgrades and changes",
    ),
    ("`document <nixos-docker-storage-driver>`", "document"),
    ("`document <nixos-opensearch>`", "document"),
]

# Old fetch-era sunsetting banner (dead platform-releases link inside):
# a bare '!!! warning' line followed by the indented one-liner.
OLD_BANNER_RE = re.compile(
    r"!!! warning\n    This is a sunsetting version[^\n]*\n\n?"
)


def fix_text(text: str) -> tuple[str, int]:
    """Apply all fixes to one page; return (new_text, fix_count)."""
    count = 0
    for old, new in FIXES:
        if old in text:
            text = text.replace(old, new)
            count += 1
    text, banners = OLD_BANNER_RE.subn("", text)
    return text, count + banners


def fix_tree(tree: Path) -> int:
    """Fix every ``*.md`` below *tree* in place; return pages changed."""
    changed = 0
    for page in sorted(tree.rglob("*.md")):
        original = page.read_text(encoding="utf-8")
        fixed, count = fix_text(original)
        if count:
            page.write_text(fixed, encoding="utf-8")
            changed += 1
    return changed
