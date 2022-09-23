#!/usr/bin/env nix-shell
#! nix-shell -i python -p "python310.withPackages (p: with p; [ GitPython rich typer ])"
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional

from git import Repo
from typer import Typer, Option, confirm, echo, Argument
from rich import print

PKG_UPDATE_RE = re.compile(
    r"(?P<name>.+): "
    r"(?P<old_version>\d.+) -> (?P<new_version>\d[^, ]+)"
    r"(?P<comment>.*)"
)

app = Typer()


class NixOSVersion(str, Enum):
    NIXOS_2205 = "nixos-22.05"
    NIXOS_2211 = "nixos-22.11"
    UNSTABLE = "nixos-unstable"


def run_on_hydra(*args):
    cmd = ["ssh", "hydra01"] + list(args)
    proc = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return proc


@dataclass
class PkgUpdate:
    name: str
    old_version: str
    new_version: str
    comments: list[str]

    @staticmethod
    def parse_msg(msg):

        match = PKG_UPDATE_RE.match(msg)

        if match is None:
            return

        name, old_version, new_version, comment = match.groups()

        clean_comment = comment.strip(" ,")
        comments = [clean_comment] if clean_comment else []

        return PkgUpdate(name, old_version, new_version, comments)

    def merge(self, other: "PkgUpdate"):
        if other is None:
            return
        if self.name != other.name:
            return
        if self.new_version != other.old_version:
            return

        return PkgUpdate(
            self.name,
            self.old_version,
            other.new_version,
            self.comments + other.comments,
        )

    def format_as_msg(self):
        update_msg = f"{self.name}: {self.old_version} -> {self.new_version}"
        if self.comments:
            return update_msg + ", " + ", ".join(self.comments)
        else:
            return update_msg


def rebase_nixpkgs(nixpkgs_repo: Repo, nixos_version: NixOSVersion):
    print("Fetching upstream remote...")
    nixpkgs_repo.git.fetch("upstream")
    old_rev = str(nixpkgs_repo.head.ref.commit)
    upstream_ref = f"upstream/{nixos_version}"
    print(f"Using upstream ref {upstream_ref}")
    nixpkgs_repo.git.rebase(upstream_ref)
    new_rev = str(nixpkgs_repo.head.ref.commit)
    version_range = f"{old_rev}..{new_rev}"
    do_push = confirm(
        f"nixpkgs rebased: {version_range}. Push now?",
        default=True,
    )
    if do_push:
        nixpkgs_repo.git.push(force=True)


def prefetch_nixpkgs(nixos_version: str) -> dict[str, str]:
    prefetch_cmd = [
        "nix-prefetch-github",
        "flyingcircusio",
        "nixpkgs",
        "--rev",
        nixos_version,
    ]

    print("Prefetching nixpkgs, this takes some time...")
    prefetch_proc = run_on_hydra(*prefetch_cmd)
    prefetch_result = json.loads(prefetch_proc.stdout)
    print(prefetch_result)
    return prefetch_result


def get_package_list():
    run_on_hydra("")


def get_interesting_commit_msgs(nixpkgs_repo, old_rev, new_rev):
    with open("package-versions.json") as f:
        package_versions = json.load(f)
    version_range = f"{old_rev}..{new_rev}"
    print(f"comparing {version_range}")
    commits = list(nixpkgs_repo.iter_commits(version_range))
    msgs = [
        c.message.splitlines()[0]
        for c in commits
        if not c.message.startswith("Merge ")
    ]
    search_words = set()
    for k, v in package_versions.items():
        search_words.add(k)
        search_words.add(v["pname"])

    return sorted({m for m in msgs if set(m.split(": ")) & search_words})


def filter_and_merge_commit_msgs(msgs):
    out_msgs = []
    last_pkg_update = None
    ignored_msgs = [
        "matomo: 4.10.1 -> 4.12.3",
        "github-runner: pass overridden version to build scripts",
        "libmodsecurity: 3.0.6 -> 3.0.7",
        "mongodb: fix build and sanitize package",
        "solr: 8.6.3 -> 8.11.1",
        "solr: 8.6.3 -> 8.11.2",
    ]

    for msg in sorted(msgs):
        if msg.startswith("linux") and ("5.10" not in msg) and ("5.15" not in msg):
            continue

        if msg in ignored_msgs:
            continue

        pkg_update = PkgUpdate.parse_msg(msg)
        if last_pkg_update:
            maybe_merged_pkg_update = last_pkg_update.merge(pkg_update)
            if maybe_merged_pkg_update:
                last_pkg_update = maybe_merged_pkg_update
            else:
                out_msgs.append(last_pkg_update.format_as_msg())
                if pkg_update is None:
                    out_msgs.append(msg)
                last_pkg_update = pkg_update
        elif pkg_update:
            last_pkg_update = pkg_update
        else:
            out_msgs.append(msg)

    if last_pkg_update:
        out_msgs.append(last_pkg_update.format_as_msg())

    return out_msgs


def update_versions_json(fc_nixos_repo: Repo, rev, sha256):
    versions_json_path = Path(fc_nixos_repo.working_dir) / "versions.json"

    with open(versions_json_path) as f:
        versions_json = json.load(f)

    versions_json["nixpkgs"]["rev"] = rev
    versions_json["nixpkgs"]["sha256"] = sha256

    with open(versions_json_path, "w") as wf:
        json.dump(versions_json, wf, indent=2)
        wf.write("\n")

    fc_nixos_repo.index.add([str(versions_json_path)])


def format_fcio_commit_msg(
    msgs: list[str], ticket_number: Optional[str]
) -> str:
    commit_msg_lines = [
        "Update nixpkgs",
        "",
        "Pull upstream NixOS changes, security fixes and package updates:",
        "",
    ]

    commit_msg_lines.extend("- " + msg for msg in msgs)
    commit_msg_lines.append("")
    if ticket_number:
        commit_msg_lines.append(f" #PL-{ticket_number}")

    return "\n".join(commit_msg_lines)


def update_fc_nixos(
    nixpkgs_repo: Repo,
    fc_nixos_repo: Repo,
    ticket_number: str,
    prefetch_json: dict[str, str],
):

    versions_json_path = Path(fc_nixos_repo.working_dir) / "versions.json"

    with open(versions_json_path) as f:
        versions_json = json.load(f)

    old_rev = versions_json["nixpkgs"]["rev"]
    new_rev = str(nixpkgs_repo.head.commit)

    update_versions_json(fc_nixos_repo, new_rev, prefetch_json["sha256"])

    interesting_msgs = get_interesting_commit_msgs(
        nixpkgs_repo, old_rev, new_rev
    )

    print("All matching new commit messages (before filter & merge):")
    for msg in interesting_msgs:
        print(msg)

    final_msgs = filter_and_merge_commit_msgs(interesting_msgs)
    commit_msg = format_fcio_commit_msg(final_msgs, ticket_number)
    print()
    print("Commit message:")
    print()
    print(commit_msg)
    feature_branch_name = f"PL-{ticket_number}-update-nixpkgs"

    if ticket_number:
        do_commit = confirm(
            f"Create feature branch ${feature_branch_name} and commit fc-nixos now?",
            default=True,
        )
    else:
        do_commit = confirm(
            f"Commit to current fc-nixos now?",
            default=True,
        )
    if do_commit:
        if ticket_number:
            branch = fc_nixos_repo.create_head(feature_branch_name)
            branch.checkout()
        fc_nixos_repo.index.commit(commit_msg)
        print(f"Committed as {fc_nixos_repo.head.ref.commit}")


@dataclass
class Context:
    nixos_version: NixOSVersion
    fc_nixos_path: Path
    nixpkgs_path: Path


context: Context


@app.callback(no_args_is_help=True)
def update_nixpkgs(
    nixos_version: NixOSVersion = Option("nixos-22.05"),
    fc_nixos_path: Path = Option(
        ".", dir_okay=True, file_okay=False, writable=True
    ),
    nixpkgs_path: Path = Option(
        ..., dir_okay=True, file_okay=False, writable=True
    ),
):
    global context
    context = Context(nixos_version, fc_nixos_path, nixpkgs_path)


@app.command(help="Update nixpkgs repo")
def nixpkgs():
    nixpkgs_repo = Repo(context.nixpkgs_path)
    rebase_nixpkgs(nixpkgs_repo, context.nixos_version)


@app.command()
def prefetch(
    nixos_version: str = Option("nixos-22.05"),
):
    print(prefetch_nixpkgs(nixos_version))


@app.command()
def fc_nixos(
    ticket_number: Optional[str] = Argument(
        None, help="Ticket number to include in the commit message"
    ),
):
    if ticket_number is not None:
        ticket_number = ticket_number.removeprefix("#")
        ticket_number = ticket_number.removeprefix("PL-")
    nixpkgs_repo = Repo(context.nixpkgs_path)
    fc_nixos_repo = Repo(context.fc_nixos_path)
    prefetch_json = prefetch_nixpkgs(context.nixos_version)
    update_fc_nixos(nixpkgs_repo, fc_nixos_repo, ticket_number, prefetch_json)


if __name__ == "__main__":
    app()
