import json
import re
import subprocess
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path
from typing import Optional

from git import Repo
from rich import print
from typer import Argument, Option, Typer, confirm

PKG_UPDATE_RE = re.compile(
    r"(?P<name>.+): "
    r"(?P<old_version>\d.+) -> (?P<new_version>\d[^, ]+)"
    r"(?P<comment>.*)"
)

NIXOS_VERSION_PATH = "release/nixos-version"
PACKAGE_VERSIONS_PATH = "release/package-versions.json"
VERSIONS_PATH = "release/versions.json"

app = Typer()


class NixOSVersion(StrEnum):
    NIXOS_2211 = "nixos-22.11"
    NIXOS_2305 = "nixos-23.05"
    NIXOS_2311 = "nixos-23.11"
    NIXOS_UNSTABLE = "nixos-24.05"

    @property
    def upstream_branch(self) -> str:
        if self == NixOSVersion.NIXOS_UNSTABLE:
            return "nixos-unstable"

        return self.value


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
    print("Fetching origin remote...")
    nixpkgs_repo.git.fetch("origin")
    origin_ref_id = f"origin/{nixos_version}"
    origin_ref = nixpkgs_repo.refs[origin_ref_id]

    if nixpkgs_repo.head.commit != origin_ref.commit:
        do_reset = confirm(
            f"local HEAD differs from {origin_ref_id}, hard-reset to origin?",
            default=True,
        )
        if do_reset:
            nixpkgs_repo.git.reset(hard=True)

    print("Fetching upstream remote...")
    nixpkgs_repo.git.fetch("upstream")
    old_rev = str(nixpkgs_repo.head.ref.commit)
    upstream_ref = f"upstream/{nixos_version.upstream_branch}"
    print(f"Using upstream ref {upstream_ref}")
    nixpkgs_repo.git.rebase(upstream_ref)
    new_rev = str(nixpkgs_repo.head.ref.commit)
    version_range = f"{old_rev}..{new_rev}"
    do_push = confirm(
        f"nixpkgs rebased: {version_range}\nPush now?",
        default=True,
    )
    if do_push:
        nixpkgs_repo.git.push(force_with_lease=True)


def version_diff_lines(old_versions, new_versions):
    lines = []
    for pkg_name in old_versions:
        old = old_versions.get(pkg_name, {}).get("version")
        new = new_versions.get(pkg_name, {}).get("version")

        if not old:
            print(f"(old version missing for {pkg_name})")
            continue

        if not new:
            print(f"(new version missing for {pkg_name})")
            continue

        if old != new:
            lines.append(f"{pkg_name}: {old} -> {new}")

    return lines


def update_package_versions_json(workdir_path: Path):
    basedir = "$XDG_RUNTIME_DIR"
    package_versions_path = workdir_path / PACKAGE_VERSIONS_PATH
    local_path = workdir_path.absolute()
    dest = f"{basedir}/{local_path.name}/"
    rsync_cmd = [
        "rsync",
        "-a",
        "--exclude",
        ".git",
        str(local_path) + "/",
        f"hydra01:{dest}",
    ]
    print("rsync: ", " ".join(rsync_cmd))
    subprocess.run(rsync_cmd, check=True)
    proc = run_on_hydra(
        f"(cd {dest};nix develop --impure --command cat_package_versions_json)"
    )
    old_versions = json.loads(package_versions_path.read_text())
    new_versions = json.loads(proc.stdout)
    print("Versions diffs:")
    for line in version_diff_lines(old_versions, new_versions):
        print(line)

    package_versions_path.write_text(json.dumps(new_versions, indent=2) + "\n")


def get_interesting_commit_msgs(
    workdir_path: Path, nixpkgs_repo, old_rev, new_rev
):
    with open(workdir_path / PACKAGE_VERSIONS_PATH) as f:
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
        search_words.add(v.get("pname"))

    return sorted({m for m in msgs if set(m.split(": ")) & search_words})


def filter_and_merge_commit_msgs(msgs):
    out_msgs = []
    last_pkg_update = None
    ignored_msgs = [
        "github-runner: pass overridden version to build scripts",
        "gitlab: make Git package configurable",
        "gitlab: remove DB migration warning",
        "jitsi-videobridge: 2.3-44-g8983b11f -> 2.3-59-g5c48e421",
        "libmodsecurity: 3.0.6 -> 3.0.7",
        "mongodb: fix build and sanitize package",
        "solr: 8.6.3 -> 8.11.1",
        "solr: 8.6.3 -> 8.11.2",
    ]

    for msg in sorted(msgs):
        if msg.startswith("linux") and "5.15" not in msg:
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
        commit_msg_lines.append(f"PL-{ticket_number}")

    return "\n".join(commit_msg_lines)


def update_fc_nixos(
    nixpkgs_repo: Repo,
    fc_nixos_repo: Repo,
    ticket_number: str,
):
    workdir_path = Path(fc_nixos_repo.working_dir)
    flake_lock_path = workdir_path / "flake.lock"
    versions_json_path = workdir_path / VERSIONS_PATH
    package_versions_path = workdir_path / PACKAGE_VERSIONS_PATH

    with open(versions_json_path) as f:
        versions_json = json.load(f)

    print(f"Updating {flake_lock_path}...")
    subprocess.run(["nix", "flake", "update"])

    print(f"Building {versions_json_path}")
    subprocess.run(["build_versions_json"])
    print()
    print("-" * 80)
    print(f"Updating {package_versions_path}...")
    update_package_versions_json(workdir_path)

    fc_nixos_repo.index.add(
        [
            str(flake_lock_path),
            str(versions_json_path),
            str(package_versions_path),
        ]
    )

    old_rev = versions_json["nixpkgs"]["rev"]
    new_rev = str(nixpkgs_repo.head.commit)

    interesting_msgs = get_interesting_commit_msgs(
        workdir_path, nixpkgs_repo, old_rev, new_rev
    )

    print("All matching new commit messages (before filter & merge):")
    for msg in interesting_msgs:
        print(msg)

    final_msgs = filter_and_merge_commit_msgs(interesting_msgs)
    commit_msg = format_fcio_commit_msg(final_msgs, ticket_number)
    print()
    print("-" * 80)
    print("Commit message:")
    print()
    print(commit_msg)
    feature_branch_name = f"PL-{ticket_number}-update-nixpkgs"

    if ticket_number:
        do_commit = confirm(
            f"Create feature branch {feature_branch_name} "
            "and commit fc-nixos now?",
            default=True,
        )
    else:
        do_commit = confirm(
            "Commit to current fc-nixos now?",
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


context: Context | None = None


@app.callback(no_args_is_help=True)
def update_nixpkgs(
    nixos_version: NixOSVersion = Option(default="nixos-23.11"),
    fc_nixos_path: Path = Option(
        ".", dir_okay=True, file_okay=False, writable=True
    ),
    nixpkgs_path: Path = Option(
        None, dir_okay=True, file_okay=False, writable=True
    ),
):
    global context
    if not nixos_version:
        version_str = (fc_nixos_path / NIXOS_VERSION_PATH).read_text().strip()
        nixos_version = NixOSVersion("nixos-" + version_str)
    context = Context(nixos_version, fc_nixos_path, nixpkgs_path)


@app.command(help="Update nixpkgs repo")
def nixpkgs():
    nixpkgs_repo = Repo(context.nixpkgs_path)
    rebase_nixpkgs(nixpkgs_repo, context.nixos_version)


@app.command()
def package_versions():
    update_package_versions_json(context.fc_nixos_path)


@app.command()
def version_diff(
    old_fc_nixos_path: Path = Argument(..., dir_okay=True, file_okay=False)
):
    """
    Shows package changes between the current (new) fc-nixos work tree and
    another (old) one based on package-versions.json.
    """
    package_versions_path = context.fc_nixos_path / PACKAGE_VERSIONS_PATH
    old_package_versions_path = old_fc_nixos_path / PACKAGE_VERSIONS_PATH
    old_versions = json.loads(old_package_versions_path.read_text())
    new_versions = json.loads(package_versions_path.read_text())

    for line in version_diff_lines(old_versions, new_versions):
        print(line)


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
    update_fc_nixos(nixpkgs_repo, fc_nixos_repo, ticket_number)


if __name__ == "__main__":
    app()
