import io
import difflib
import fcntl
import os
import sys


class ConfigFile(object):
    """Wrapper for writing configuration files.

    ConfigFile is a StringIO-like object which is able to write out it's
    contents to a file if it is different from the on-disk version.
    """

    quiet = False

    def __init__(self, filename, stdout=None, mode=0o666):
        """Create ConfigFile object.

        Parameters:
            filename - config file to write to
            stdout - io stream to use for diffs
        """
        self.filename = filename
        self.io = io.StringIO()
        self.stdout = stdout
        self.changed = False
        self.mode = mode

        if stdout is not None:
            self.stdout = stdout
        elif not self.quiet:
            self.stdout = sys.stdout
        else:
            self.stdout = io.StringIO()

    def _diff(self):
        """Dump diff between old and new to stdout."""
        self.io.seek(0)
        self.stdout.writelines(difflib.unified_diff(
            open(self.filename).readlines(), self.io.readlines(),
            self.filename + ' (old)', self.filename + ' (new)'))

    def _writeout(self, outfile):
        """Write contents unconditionally to file."""
        outfile.seek(0)
        outfile.truncate()
        outfile.write(self.io.getvalue())
        outfile.flush()
        if hasattr(os, 'fdatasync'):
            os.fdatasync(outfile)
        else:
            # OS X
            fcntl.fcntl(outfile, fcntl.F_FULLFSYNC)
        self.changed = True

    def _update(self):
        """Update already existing file."""
        with open(self.filename, 'r+') as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            old = f.read()
            if self.io.getvalue() != old:
                self._diff()
                fcntl.flock(f, fcntl.LOCK_EX)
                self._writeout(f)

    def _create(self):
        """Write contents to new file.

        I prefer to use os.open because we can make sure that *we* are
        actually creating the file and there is no race condition.
        """
        fd = os.open(self.filename, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                     self.mode)
        fcntl.flock(fd, fcntl.LOCK_EX)
        with os.fdopen(fd, 'w') as f:
            self._writeout(f)

    def commit(self):
        """Write contents into file if different.

        No more I/O is possible on this ConfigFile instance afterwards. While
        comparing the real file, the file is locked to prevent race conditions.
        A diff between the new and old file contents is written to stdout.
        Return true if the file has been changed.
        """
        if os.path.exists(self.filename):
            self._update()
        else:
            self._create()
        self.io.close()
        return self.changed

    def __getattr__(self, name):
        """Pass everything else to underlying StringIO object."""
        return self.io.__getattribute__(name)
