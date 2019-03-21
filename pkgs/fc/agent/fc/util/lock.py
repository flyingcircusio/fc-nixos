import contextlib
import fcntl
import os


@contextlib.contextmanager
def locked(lockfile):
    """Execute the associated with-block exclusively.

    A lockfile will be created as necessary. Once the exclusive lock has
    been acquired, the current PID is recorded to assist debugging in
    case of need.
    """
    # touch into existence
    open(lockfile, 'a').close()
    with open(lockfile, 'r+', buffering=1) as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.truncate(0)
        f.seek(0)
        print(os.getpid(), file=f)
        yield
        f.truncate(0)
