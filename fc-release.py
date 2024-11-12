#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p scriv

import argparse
import re
import sys
from pathlib import Path
from subprocess import CalledProcessError, run

ORIGIN_REMOTE_PATTERN = re.compile(
    r"^origin\s.*github.com.flyingcircusio/fc-nixos"
)
DOCS_REMOTE_PATTERN = re.compile(r"^origin\s.*github.com.flyingcircusio/doc")
STEPS = ["prepare", "changelog", "merge", "backmerge", "push"]
TEMP_CHANGELOG = Path("changelog.d/CHANGELOG.md.tmp")
CHANGELOG = Path("changelog.d/CHANGELOG.md")


def release_id_type(arg_value):
    if not re.compile("^[0-9]{4}_[0-9]{3}$").match(arg_value):
        raise argparse.ArgumentTypeError(
            "invalid release id format. Expected: YYYY_NNN"
        )
    return arg_value


def git_remote(repo=Path(".")):
    return run(
        ["git", "-C", str(repo), "remote", "-v"], capture_output=True
    ).stdout.decode()


class Release:
    def __init__(self, release_id: str):
        self.release_id = release_id
        with Path("nixos-version").open() as f:
            self.nixos_version = f.read().strip()

        self.branch_dev = f"fc-{self.nixos_version}-dev"
        self.branch_stag = f"fc-{self.nixos_version}-staging"
        self.branch_prod = f"fc-{self.nixos_version}-production"

    def prepare(self):
        remotes = git_remote()
        if not ORIGIN_REMOTE_PATTERN.match(remotes):
            print(
                "please perform release in a clean checkout with proper origin"
            )
            sys.exit(64)

        run(["git", "fetch", "origin", "--tags", "--prune"], check=True)
        run(["git", "checkout", self.branch_dev], check=True)
        run(
            ["git", "merge", "--ff-only"], check=True
        )  # expected to fail on unclean/unpushed workdirs
        run(["git", "checkout", self.branch_stag], check=True)
        run(["git", "merge", "--ff-only"], check=True)

    def changelog(self):
        doc_repo = Path("../doc")
        if not (doc_repo / "changelog.d").is_dir():
            print(
                "please ensure that you have a checkout of "
                "`flyingcircusio/doc` next to this repo"
            )
            sys.exit(64)

        doc_remotes = git_remote(doc_repo)
        if not DOCS_REMOTE_PATTERN.match(doc_remotes):
            print("doc repo has unexpected origin")
            sys.exit(64)

        doc_fragment_path = (
            doc_repo / "changelog.d" / f"{self.nixos_version}.md"
        )
        if doc_fragment_path.exists():
            print(
                f"the changelog fragment '{doc_fragment_path}' already exists\n"
                + "Remove it or skip changelog generation"
            )
            sys.exit(64)

        TEMP_CHANGELOG.open("w").close()  # truncate
        try:
            run(["scriv", "collect", "--add"], check=True)
        except CalledProcessError:
            TEMP_CHANGELOG.unlink()
            print(
                "Failed to collect Changelog. You can skip this by omitting the `changelog` stage."
            )
            raise

        new_fragment = TEMP_CHANGELOG.read_text()
        doc_fragment = new_fragment.replace(
            "\n## Impact", f"\n## Impact\n### {self.nixos_version}"
        )
        doc_fragment = doc_fragment.replace(
            "\n## NixOS XX.XX platform",
            f"\n## NixOS {self.nixos_version} platform",
        )
        doc_fragment_path.write_text(doc_fragment)

        new_changelog = f"# Release {self.release_id}\n\n" + new_fragment
        if CHANGELOG.exists():
            new_changelog += "\n" + CHANGELOG.read_text()
        CHANGELOG.write_text(new_changelog)

        TEMP_CHANGELOG.unlink()

        try:
            run(["git", "add", str(TEMP_CHANGELOG), str(CHANGELOG)], check=True)
            run(
                ["git", "commit", "-m", "Collect changelog fragments"],
                check=True,
            )
        except CalledProcessError:
            print(
                "Failed to commit Changelog. Commit it manually and continue after the `changelog` stage"
            )
            raise

    def merge(self):
        # Ensure the upstream/tracked production branch is clean compared
        # to our local branch.
        run(["git", "checkout", self.branch_prod], check=True)
        run(["git", "merge", "--ff-only"], check=True)

        msg = (
            f"Merge branch '{self.branch_stag}' into "
            f"'{self.branch_prod}' for release {self.release_id}"
        )
        run(["git", "merge", "-m", msg, self.branch_stag], check=True)

    def backmerge(self):
        run(["git", "checkout", self.branch_dev], check=True)
        msg = f"Backmerge branch '{self.branch_prod}' into '{self.branch_dev}'' for release {self.release_id}"
        run(["git", "merge", "-m", msg, self.branch_prod], check=True)

    def push(self):
        print("Committed changes:")
        run(
            ["git", "log", "--graph", "--decorate", "--format=short", "-n3"],
            env={"PAGER": ""},
            check=True,
        )
        cmd = f"git push origin {self.branch_dev} {self.branch_stag} {self.branch_prod}"
        print(
            "If this looks correct, press Enter to push (or use ^C to abort)."
        )
        print(f"This will issue: `{cmd}`")
        input()
        run(cmd, shell=True, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("release_id", type=release_id_type)
    parser.add_argument(
        "steps", choices=["all"] + STEPS, default="all", nargs="*"
    )
    args = parser.parse_args()
    if args.steps == "all" or "all" in args.steps:
        args.steps = STEPS

    release = Release(args.release_id)
    print(f"Performing release for {args.release_id}")
    for step_name in args.steps:
        print(f"Release step: {step_name}")
        getattr(release, step_name)()


if __name__ == "__main__":
    main()
