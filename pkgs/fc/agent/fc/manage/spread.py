import datetime
import logging
import os
import random
import time

_log = logging.getLogger(__name__)


def _fmt_time(timestamp, sep=" "):
    return datetime.datetime.fromtimestamp(timestamp).isoformat(sep=sep)


class Spread:
    def __init__(self, stampfile, interval=120 * 60, jobname="Job"):
        self.stampfile = stampfile
        self.interval = interval
        self.jobname = jobname
        self.offset = None

    def generate(self):
        """Generates random offset and writes it to the stamp file."""
        self.offset = random.randint(0, self.interval)
        _log.info("Randomizing offset for %s to %s", self.jobname, self.offset)
        with open(self.stampfile, "w") as f:
            print(self.offset, file=f)
        os.utime(self.stampfile, (0, 0))

    def configure(self):
        """Reads or generates offset. Returns configured object"""
        try:
            with open(self.stampfile) as f:
                self.offset = int(f.read())
        except (FileNotFoundError, TypeError):
            self.generate()
            return self
        if self.offset > self.interval:
            self.generate()
        return self

    def touch(self, reference=time.time()):
        """Updates stamp file. Takes offset into account."""
        t = time.time() - self.offset
        os.utime(self.stampfile, (t, t))

    def next_due(self):
        """Returns next due date as POSIX timestamp."""
        mtime = os.stat(self.stampfile).st_mtime
        elapsed = mtime % self.interval
        return mtime - elapsed + self.interval + self.offset

    def is_due(self):
        """Returns true if job is due. Updates stamp file."""
        due = self.next_due()
        now = time.time()
        if now >= due:
            _log.info("%s was due at %s", self.jobname, _fmt_time(due))
            self.touch(now)
            return True
        else:
            _log.info("%s is due at %s", self.jobname, _fmt_time(due))
            return False


class NullSpread:
    """Stripped down version of `Spread` which is always due."""

    stampfile = None
    interval = 0
    jobname = ""
    offset = None

    def __init__(self, stampfile=None, interval=0, jobname=""):
        pass

    def generate(self):
        pass

    def configure(self):
        pass

    def touch(self, reference=None):
        pass

    def next_due(self):
        """Always due."""
        return time.time()

    def is_due(self):
        """Always due."""
        return True
