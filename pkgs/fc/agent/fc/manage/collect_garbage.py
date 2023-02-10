import datetime
import os
import pwd
import subprocess
from pathlib import Path

import fc.util.lock
import structlog
from fc.util.logging import init_logging
from typer import Exit, Option, Typer

app = Typer()

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
def collect_garbage(
    verbose: bool = Option(
        False, "--verbose", "-v", help="Show debug messages and code locations."
    ),
    exclude_file: Path = Option(
        exists=True,
        file_okay=True,
        dir_okay=False,
        readable=True,
        default="/etc/userscan/exclude",
        help="File with exclude rules for fc-userscan",
    ),
    stamp_dir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/var/log",
        help="Location for the file with the last successful run timestamp.",
    ),
    lock_dir: Path = Option(
        exists=True,
        file_okay=False,
        writable=True,
        default="/run/lock",
        help="Where the lock file for exclusive operations should be placed.",
    ),
):
    init_logging(verbose, syslog_identifier="fc-collect-garbage")
    log = structlog.get_logger()

    log.debug("collect-garbage-start")

    return_codes = []
    users_to_scan = [
        user
        for user in pwd.getpwall()
        if user.pw_uid >= 1000 and user.pw_dir != "/var/empty"
    ]
    log.info(
        "userscan-start",
        _replace_msg="Running fc-userscan for {user_count} users",
        user_count=len(users_to_scan),
    )

    for user in users_to_scan:
        log.debug(
            "userscan-user",
            _replace_msg="Scanning {homedir} as {name}",
            homedir=user.pw_dir,
            name=user.pw_name,
        )

        p = subprocess.Popen(
            [
                "fc-userscan",
                "--register",
                "--cache",
                user.pw_dir + "/.cache/fc-userscan.cache",
                "--cache-limit",
                "10000000",
                "--unzip=*.egg",
                "--excludefrom",
                exclude_file,
                user.pw_dir,
            ],
            stdin=subprocess.DEVNULL,
            preexec_fn=lambda: os.setresuid(user.pw_uid, 0, 0),
        )
        rc = p.wait()
        log.debug("userscan-result", rc=rc)
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

    log.info(
        "collect-garbage-start", _replace_msg="Running nix-collect-garbage."
    )

    # The lock makes sure that garbage collection doesn't run concurrently
    # with fc-manage commands which build the system or other invocations of
    # fc-collect-garbage.
    # This should avoid situations where nix-collect-garbage cannot lock the
    # Nix DB which can cause store paths that remain in the Nix DB despite being
    # deleted from the Nix store.
    with fc.util.lock.locked(log, lock_dir):
        rc = subprocess.run(
            ["nix-collect-garbage", "--delete-older-than", "3d"],
            check=True,
            stdin=subprocess.DEVNULL,
        ).returncode

    if rc > 0:
        log.error(
            "collect-garbage-failed"
            "nix-collect-garbage failed with status {rc}. "
            "See above for command output.",
            rc=rc,
        )
        raise Exit(3)

    stamp_file = stamp_dir / "fc-collect-garbage.log"
    stamp_file.write_text(str(datetime.datetime.now()) + "\n")

    log.info(
        "collect-garbage-succeeded",
        _replace_msg="fc-collect-garbage finished without problems.",
    )
