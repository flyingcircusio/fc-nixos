import time


class TimeoutError(RuntimeError):
    pass


class TimeOut(object):
    _now = time.time

    def __init__(self, timeout, interval=1, raise_on_timeout=False):
        self.cutoff = self._now() + timeout
        self.interval = interval
        self.timed_out = False
        self.first = True
        self.raise_on_timeout = raise_on_timeout

    @property
    def remaining(self):
        return int(self.cutoff - self._now())

    def tick(self):
        """Perform a `tick` for this timeout.

        Returns True if we should keep going or False if not.

        Instead of returning False this can raise an exception
        if raise_on_timeout is set.

        """
        remaining = self.remaining  # make atomic within this function
        self.timed_out = remaining <= 0

        if self.timed_out:
            if self.raise_on_timeout:
                raise TimeoutError()
            else:
                return False

        if self.first:
            self.first = False
        else:
            time.sleep(self.interval)

        return True
