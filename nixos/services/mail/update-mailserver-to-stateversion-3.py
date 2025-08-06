# This is a modified version of https://gitlab.com/simple-nixos-mailserver/nixos-mailserver/-/blob/master/migrations/nixos-mailserver-migration-03.py
# that is able to run automatically

import argparse
import os
import shutil
import sys
from enum import Enum
from pathlib import Path
from pwd import getpwnam


class FolderLayout(Enum):
    Default = 1
    Folder = 2


def check_user(vmail_root: Path):
    owner = vmail_root.owner()
    owner_uid = getpwnam(owner).pw_uid

    if os.geteuid() == owner_uid:
        return

    try:
        print(
            f"Trying to switch effective user id to {owner_uid} ({owner})",
            file=sys.stderr,
        )
        os.seteuid(owner_uid)
        return
    except PermissionError:
        print(
            f"Failed switching to virtual mail user. Please run this script under it, for example by using `sudo -u {owner}`)",
            file=sys.stderr,
        )
    sys.exit(1)


def is_maildir_related(path: Path, layout: FolderLayout) -> bool:
    if path.name in [
        "subscriptions",
        # https://doc.dovecot.org/2.3/admin_manual/mailbox_formats/maildir/#imap-uid-mapping
        "dovecot-uidlist",
        # https://doc.dovecot.org/2.3/admin_manual/mailbox_formats/maildir/#imap-keywords
        "dovecot-keywords",
    ]:
        return True
    if not path.is_dir():
        return False
    if path.name in ["cur", "new", "tmp"]:
        return True
    if layout is FolderLayout.Default and path.name.startswith("."):
        return True
    if layout is FolderLayout.Folder:
        if path.name in ["mail"]:
            return False
        return True

    return False


def mkdir(dst: Path, dry_run: bool = True):
    print(f'mkdir "{dst}"')
    if not dry_run:
        # u+rwx, setgid
        dst.mkdir(mode=0o2700)


def move(src: Path, dst: Path, dry_run: bool = True):
    print(f'mv "{src}" "{dst}"')
    if not dry_run:
        src.rename(dst)


def delete(dst: Path, dry_run: bool = True):
    if not dst.exists():
        return

    if dst.is_dir():
        print(f'rm --recursive "{dst}"')
        if not dry_run:
            shutil.rmtree(dst)
    else:
        print(f'rm "{dst}"')
        if not dry_run:
            dst.unlink()


def main(vmail_root: Path, layout: FolderLayout, dry_run: bool = True):
    maildirs = {path.parent for path in vmail_root.glob("*/*/cur")}
    maybe_delete = []

    # The old maildir will be the new home directory
    for homedir in maildirs:
        maildir = homedir / "mail"
        mkdir(maildir, dry_run)

        for path in homedir.iterdir():
            if is_maildir_related(path, layout):
                move(path, maildir / path.name, dry_run)
            else:
                maybe_delete.append(path)

    # Files that are part of the previous home directory, but now obsolete
    for path in [
        vmail_root / ".dovecot.lda-dupes",
        vmail_root / ".dovecot.lda-dupes.locks",
    ]:
        delete(path, dry_run)

    # The remaining files are likely obsolete, but should still be checked with care
    for path in maybe_delete:
        print(f"# rm {str(path)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="""
        NixOS Mailserver Migration #3: Dovecot mail directory migration
        (https://nixos-mailserver.readthedocs.io/en/latest/migrations.html#dovecot-mail-directory-migration)
    """
    )
    parser.add_argument(
        "vmail_root", type=Path, help="Path to the `mailserver.mailDirectory`"
    )
    parser.add_argument(
        "--layout",
        choices=["default", "folder"],
        required=True,
        help="Folder layout: 'default' unless `mailserver.useFsLayout` was enabled, then'folder'",
    )

    args = parser.parse_args()

    layout = (
        FolderLayout.Default
        if args.layout == "default"
        else FolderLayout.Folder
    )

    check_user(args.vmail_root)
    main(args.vmail_root, layout, dry_run=False)
