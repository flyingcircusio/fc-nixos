#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3

# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Emily Lange <git@emilylange.de>

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from pwd import getpwnam

EXIT_OK = 0
EXIT_ERROR = 1

GREEN = "32"
YELLOW = "33"
RED = "31"
BOLD = "1"

NO_COLOR = "NO_COLOR" in os.environ


def color(text, code):
    if NO_COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"


def check_user(sieve_root: Path):
    owner = sieve_root.owner()
    owner_uid = getpwnam(owner).pw_uid

    if os.geteuid() == owner_uid:
        return

    try:
        print(f"Trying to switch effective user id to {owner_uid} ({owner})")
        os.seteuid(owner_uid)
        return
    except PermissionError:
        print(
            f"Failed switching to virtual mail user. Please run this script under it, for example by using `sudo -u {owner}`)"
        )
    sys.exit(1)


def doveadm_get_user_home(user: str) -> Path:
    output = subprocess.check_output(
        ["doveadm", "user", "-f", "home", user],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    homedir = Path(output.strip())
    return homedir


def move(src: Path, dst: Path, dry_run: bool = True) -> bool:
    print(f'mv "{src}" "{dst}"')
    if not dry_run:
        try:
            shutil.move(src, dst)
        except OSError as exc:
            print(f"Rename failed ({src=!s}, {dst=!s}): {exc}")
            return False
    return True


def symlink(target: Path, link: Path, dry_run: bool = True) -> bool:
    print(f'ln --symbolic --relative "{target}" "{link}"')
    if not dry_run:
        try:
            target_relative = target.relative_to(link.parent)
            link.symlink_to(target_relative)
        except (OSError, ValueError) as exc:
            print(f"Symlinking failed ({target=!s}, {link=!s}): {exc}")
            return False
    return True


def main(sieve_root: Path, dry_run: bool = True):
    print(
        color(
            f"\nFind accounts based on existing Sieve script directories in {sieve_root!s}",
            BOLD,
        )
    )

    skipped = 0
    accounts = set()
    for path in sieve_root.glob("*"):
        if not path.is_dir():
            print(f"- Not a directory ({path=!s}) (skipping)")
            skipped += 1
            continue
        elif not set(path.glob("scripts/*.sieve")):
            print(f"- No Sieve scripts in directory ({path=!s}) (skipping)")
            skipped += 1
            continue

        account = path.name
        accounts.add(account)
        print(f"- Sieve directory found ({path=!s}, {account=})")

    print(
        color(
            f"\nLookup home directory of accounts based on the remaining Sieve directories found in {sieve_root!s}",
            BOLD,
        )
    )

    lookup_failed = 0
    homedirs = {}
    for account in accounts:
        try:
            homedir = doveadm_get_user_home(account)
        except subprocess.CalledProcessError as exc:
            print(f"- Home directory lookup failed ({account=}): {exc}")
            lookup_failed += 1
            continue
        print(f"- Home directory retrieved ({account=}, {homedir=!s})")
        homedirs.update({account: homedir})

    print(
        color(
            "\nEnumerate Sieve directories of accounts",
            BOLD,
        )
    )

    plan = {}
    for account, homedir in homedirs.items():
        sieve_src = sieve_root / account / "scripts"
        sieve_dst = homedir / "sieve"
        plan.update({sieve_src: sieve_dst})

        active = sieve_root / account / "active.sieve"
        link = homedir / ".dovecot.sieve"
        # An account may have Sieve scripts but none enabled,
        # e.g. an out-of-office auto-reply but currently in-office.
        if not active.is_symlink():
            print(
                f"- Account has Sieve scripts but none enabled ({account=}, {active=!s})"
            )
            continue
        active_relative = active.resolve().relative_to(sieve_src)
        target = sieve_dst / active_relative
        plan.update({target: link})
        print(
            f"- Account has Sieve scripts and one enabled ({account=}, {sieve_src=!s})"
        )

    print(color("\nThe following operations will be executed:", BOLD))
    moved = 0
    moves_failed = 0
    for src, dst in plan.items():
        if src.is_dir():
            if not move(src=src, dst=dst, dry_run=dry_run):
                moves_failed += 1
            else:
                moved += 1
        else:
            if not symlink(target=src, link=dst, dry_run=dry_run):
                moves_failed += 1
            else:
                moved += 1

    print(
        color(
            "\nMigration summary",
            BOLD,
        )
    )

    if any([skipped, lookup_failed, not accounts, moves_failed]):
        print("""
We strongly recommend reviewing and remediating all potential issues before
running with `--execute`. Specific details can be found further up.""")

    if moved:
        print(f"""
- {color(f"{moved} Sieve script directories were migrated successfully.", GREEN)} {"(dry run)" if dry_run else ""}""")

    if skipped and accounts:
        print(f"""
- {color(f"{skipped} paths in {(sieve_root)!s} were skipped.", YELLOW)}
  These were not a directory or did not contain a ./scripts directory.
  They should be reviewed but can most likely be deleted.""")

    if lookup_failed:
        print(f"""
- {color(f"{lookup_failed} account lookups failed.", YELLOW)}
  This could be a problem, because we cannot migrate the Sieve script
  directory into the home directory without finding the owner of the
  directory. In practice this can happen if an account was deleted but
  its Sieve script directory remained.""")

    if not accounts:
        print(f"""
- {color("No Sieve script directories were found.", RED)}
  Make sure you are passing the correct `sieve_root` argument. It must match
  your `mailserver.sieveDirectory` setting. In practise this may also happen
  if simply no account has Sieve scripts.""")

    if moves_failed:
        print(f"""
- {color(f"{moves_failed} Sieve script directories could not be renamed", RED)}
  No reason to panic, but the script tried to rename a Sieve script directory
  and that triggered and error. Check further up what went wrong.""")

    if dry_run:
        print(f"\n{color('No changes were made.', YELLOW)}")
        print("Run the script with `--execute` to apply the listed changes.")

    sys.exit(EXIT_OK if moves_failed == 0 else EXIT_ERROR)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="""
        NixOS Mailserver Migration #5: Sieve script directory migration
        (https://nixos-mailserver.readthedocs.io/en/latest/migrations.html#sieve-script-directory-migration)
    """
    )
    parser.add_argument(
        "sieve_root", type=Path, help="Path to the `mailserver.sieveDirectory`"
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Actually perform changes",
        default=True,
    )

    args = parser.parse_args()

    check_user(args.sieve_root)
    main(
        sieve_root=args.sieve_root,
        dry_run=not args.execute,
    )
