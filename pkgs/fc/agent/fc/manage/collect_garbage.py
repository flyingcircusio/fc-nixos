import datetime
import os
import pwd
import subprocess
from pathlib import Path

import fc.util.lock
import structlog
from fc.util.logging import init_command_logging, init_logging
from fc.util.subprocess_helper import get_popen_stderr_lines
from fc.util.typer_utils import FCTyperApp, requires_sudo
from typer import Exit, Option
from typing_extensions import Annotated

app = FCTyperApp("fc-collect-garbage")

HELP = """
Clean up unused Nix store paths.

This runs in two phases:

1. Run `fc-userscan` for all human and service users to find Nix store
   references that should be kept. fc-userscan creates garbage collector roots
   to protect them from being removed.
2. Run `nix-collect-garbage` to actually clean up the Nix store.

If something goes wrong in step 1, garbage collection will not run to protect
Nix store paths that may be still referenced from home dirs.
"""


@app.command(help=HELP)
@requires_sudo
def collect_garbage(
    dry_run_for_user: Annotated[
        str,
        Option(
            help="Show what fc-userscan would do and dry-run garbage-collection"
        ),
    ] = None,
    max_age: Annotated[
        str,
        Option(help="Delete generations older than..."),
    ] = "3d",
    verbose: Annotated[bool, Option("--verbose", "-v")] = False,
    exclude_file: Annotated[
        Path,
        Option(
            exists=True,
            file_okay=True,
            dir_okay=False,
            help="File with exclude rules for fc-userscan",
        ),
    ] = "/etc/fc-userscan/exclude-patterns",
    ignore_users_file: Annotated[
        Path,
        Option(
            exists=True,
            file_okay=True,
            dir_okay=False,
            help="File with names of users to ignore for fc-userscan",
        ),
    ] = "/etc/fc-userscan/ignore-users",
    stamp_file: Annotated[
        Path,
        Option(
            file_okay=True,
            dir_okay=False,
            writable=True,
            help="Where the last successful run timestamp is written to.",
        ),
    ] = None,
    logdir: Annotated[
        Path,
        Option(
            file_okay=False,
            help="Directory for log files.",
        ),
    ] = "/var/log",
    lock_dir: Annotated[
        Path,
        Option(
            exists=True,
            file_okay=False,
            help="Where the lock file for exclusive operations should be placed.",
        ),
    ] = "/run/lock",
):
    init_logging(verbose, logdir, syslog_identifier="fc-collect-garbage")
    log = structlog.get_logger()

    log.debug("fc-collect-garbage-start")
    init_command_logging(log, identifier="fc-collect-garbage")

    run_userscan(
        log, exclude_file, ignore_users_file, verbose, dry_run_for_user
    )

    run_nix_collect_garbage(log, lock_dir, bool(dry_run_for_user), max_age)

    log.debug("stamp-file", filename=stamp_file)

    if stamp_file is not None:
        stamp_file.write_text(str(datetime.datetime.now()) + "\n")


def run_userscan(
    log,
    exclude_file: Path,
    ignore_users_file: Path,
    verbose: bool,
    dry_run_for_user=None,
):
    return_codes = []

    if dry_run_for_user:
        users_to_scan = [pwd.getpwnam(dry_run_for_user)]
        log.info(
            "userscan-dry-run-for-user",
            name=dry_run_for_user,
            _replace_msg=(
                "Dry-running for user {name}, just logging what fc-userscan "
                "would do."
            ),
        )
    else:
        with ignore_users_file.open("r") as f:
            ignore_users = set([x.strip() for x in f])
        users_to_scan = [
            user
            for user in pwd.getpwall()
            if user.pw_uid >= 1000
            and user.pw_dir != "/var/empty"
            and user.pw_name not in ignore_users
        ]
        log.info(
            "userscan-start",
            _replace_msg="Running fc-userscan for {user_count} users",
            user_count=len(users_to_scan),
        )

    for user in users_to_scan:
        home_dir = Path(user.pw_dir)
        cache_file = home_dir / ".cache/fc-userscan.cache"
        user_specific_ignore_file = home_dir / ".userscan-ignore"

        user_log = log.bind(name=user.pw_name)

        user_log.info(
            "userscan-user",
            _replace_msg="Scanning {homedir}",
            homedir=home_dir,
        )

        if cache_file.exists():
            user_log.debug(
                "userscan-cache-found",
                path=cache_file,
                size=cache_file.stat().st_size,
                owner=cache_file.owner(),
            )
        else:
            user_log.debug(
                "userscan-cache-not-found",
                path=cache_file,
            )

        userscan_cmd = [
            "fc-userscan",
            "--list" if dry_run_for_user else "--register",
            "--cache",
            cache_file,
            "--cache-limit",
            "10000000",
            "--unzip=*.egg",
            "--excludefrom",
            exclude_file,
            home_dir,
        ]

        if user_specific_ignore_file.exists():
            user_log.debug(
                "userscan-ignore-found",
                path=user_specific_ignore_file,
                size=user_specific_ignore_file.stat().st_size,
                owner=user_specific_ignore_file.owner(),
            )

            userscan_cmd.extend(["--excludefrom", user_specific_ignore_file])
        else:
            user_log.debug(
                "userscan-ignore-not-found",
                path=user_specific_ignore_file,
            )

        if verbose:
            userscan_cmd.append("--verbose")

        user_log.debug("userscan-cmd", cmd=userscan_cmd)

        proc = subprocess.Popen(
            userscan_cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        # FIXME: unused variable, will this be used in the future?
        # stderr_lines = get_popen_stderr_lines(proc, log, "userscan-out")
        # stderr = "".join(stderr_lines).strip()
        rc = proc.wait()

        user_log.debug("userscan-result", rc=rc, stdout=proc.stdout.read())
        return_codes.append(rc)
    status = max(return_codes)
    log.debug(
        "userscan-max-status",
        status=status,
    )
    if status:
        log.error(
            "userscan-failed",
            _replace_msg="fc-userscan failed. See above for errors.",
            status=status,
        )

        raise Exit(status)


def run_nix_collect_garbage(log, lock_dir: Path, dry_run=False, max_age="3d"):
    collect_garbage_cmd = [
        "nix-collect-garbage",
        "--delete-older-than",
        max_age,
    ]
    if dry_run:
        collect_garbage_cmd.append("--dry-run")
        log.info(
            "collect-garbage-dry-run",
            _replace_msg="Dry-running nix-collect-garbage (no removals).",
        )
    else:
        log.info(
            "collect-garbage-start",
            _replace_msg="Running nix-collect-garbage.",
        )
    # The lock makes sure that garbage collection doesn't run concurrently
    # with fc-manage commands which build the system or other invocations of
    # fc-collect-garbage.
    # This should avoid situations where nix-collect-garbage cannot lock the
    # Nix DB which can cause store paths that remain in the Nix DB despite being
    # deleted from the Nix store.
    with fc.util.lock.locked(log, lock_dir):
        proc = subprocess.Popen(
            collect_garbage_cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        stderr_lines = get_popen_stderr_lines(proc, log, "collect-garbage-out")
        stderr = "".join(stderr_lines).strip()
        rc = proc.wait()

    if rc > 0:
        log.error(
            "collect-garbage-failed"
            "nix-collect-garbage failed with status {rc}. "
            "See above for command output.",
            rc=rc,
            stderr=stderr,
        )
        raise Exit(3)
    log.info(
        "collect-garbage-succeeded",
        _replace_msg="fc-collect-garbage finished without problems.",
    )


if __name__ == "__main__":
    app()
