import contextlib
import fcntl
import os
from pathlib import Path


@contextlib.contextmanager
def locked(log, lockdir, lockfile_name="fc-agent.lock"):
    """Execute the associated with-block exclusively.

    A lockfile will be created as necessary. Once the exclusive lock has
    been acquired, the current PID is recorded to assist debugging in
    case of need.
    """

    lockfile = Path(lockdir) / lockfile_name

    if not lockfile.exists():
        lockfile.touch()

    with open(lockfile, "r+", buffering=1) as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            other_pid = f.read().strip() or "<unknown>"
            log.info(
                "lock-try",
                lockfile=str(lockfile),
                other_pid=other_pid,
                _replace_msg=(
                    "Looks like another management command is running, waiting "
                    "for {lockfile} locked by PID {other_pid} (no timeout) ..."
                ),
            )
            fcntl.flock(f, fcntl.LOCK_EX)

        f.truncate(0)
        f.seek(0)
        print(os.getpid(), file=f)
        log.debug(
            "lock-locked",
            _replace_msg="Locked {lockfile}",
            lockfile=lockfile,
        )
        yield
        f.truncate(0)
        fcntl.flock(f, fcntl.LOCK_UN)
        log.debug(
            "lock-released",
            _replace_msg="Released {lockfile} from PID {pid}",
            lockfile=lockfile,
        )
