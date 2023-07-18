import contextlib
import copy
import datetime
import os
import os.path as p
import tempfile

import iso8601
import pytz
import shortuuid
import structlog
import yaml

from .estimate import Estimate
from .state import State, evaluate_state

_log = structlog.get_logger()


def utcnow():
    return pytz.UTC.localize(datetime.datetime.utcnow())


@contextlib.contextmanager
def cd(newdir):
    oldcwd = os.getcwd()
    os.chdir(newdir)
    try:
        yield
    finally:
        os.chdir(oldcwd)


class Request:

    MAX_RETRIES = 48

    _reqid = None
    activity = None
    comment = None
    estimate = None
    next_due = None
    state = State.pending
    _reqmanager = None  # backpointer, will be set in ReqManager

    def __init__(self, activity, estimate, comment=None, dir=None, log=_log):
        activity.request = self
        self.activity = activity
        self.estimate = Estimate(estimate)
        self.comment = comment
        self.dir = dir
        self.log = log
        self.attempts = []

    def __str__(self):
        line = "{state}  {shortid}  {sched:20}  {estimate:8}  {comment}".format(
            state=self.state.short,
            shortid=self.id[:7],
            sched=(
                self.next_due.strftime("%Y-%m-%d %H:%M UTC")
                if self.next_due
                else "--- TBA ---"
            ),
            estimate=str(self.estimate),
            comment=self.comment,
        )
        if self.duration:
            line += " (duration: {})".format(Estimate(self.duration))
        return line

    def __eq__(self, other):
        return self.__class__ == other.__class__ and self.id == other.id

    def __getstate__(self):
        state = self.__dict__.copy()
        # This somehow gets called twice when serializing to YAML so the second
        # time, log may be mising. Just ignore it.
        if "log" in state:
            del state["log"]
        return state

    def __hash__(self):
        return hash(self.id)

    def __lt__(self, other):
        if self.next_due and other.next_due:
            return self.next_due < other.next_due
        elif self.next_due:
            return True
        elif other.next_due:
            return False
        else:
            return self.id < other.id

    def set_up_logging(self, log):
        log = log.bind(request=self.id)
        self.log = log
        self.activity.set_up_logging(log)

    @property
    def id(self):
        """Unique request id. Generated on first access."""
        if not self._reqid:
            self._reqid = shortuuid.uuid()
        return self._reqid

    @property
    def duration(self):
        """Duration of the last attempt in seconds (float)."""
        if self.attempts:
            return self.attempts[-1].duration

    @property
    def filename(self):
        """Full path to request.yaml."""
        return p.join(self.dir, "request.yaml")

    @classmethod
    def load(cls, dir, log):
        # need imports because such objects may be loaded via YAML
        import fc.maintenance.activity.update
        import fc.maintenance.lib.reboot
        import fc.maintenance.lib.shellscript

        with open(p.join(dir, "request.yaml")) as f:
            instance = yaml.load(f, Loader=yaml.FullLoader)
            if instance.next_due and not instance.next_due.tzinfo:
                instance.next_due = pytz.UTC.localize(instance.next_due)
        instance.dir = dir
        with cd(dir):
            instance.activity.load()
        instance.set_up_logging(log)
        return instance

    def save(self):
        assert self.dir, "request directory not set"
        if not p.isdir(self.dir):
            os.mkdir(self.dir)
        with tempfile.NamedTemporaryFile(
            mode="w", dir=self.dir, delete=False
        ) as tf:
            yaml.dump(self, tf)
            tf.flush()
            os.fsync(tf.fileno())
            os.chmod(tf.fileno(), 0o644)
            os.rename(tf.name, self.filename)
        with cd(self.dir):
            self.activity.dump()

    def execute(self):
        """Executes associated activity.

        Execution takes place in the request's scratch directory.
        Each attempt records outcomes so that the Activity object may
        overwrite stdout, stderr, and returncode after each attempt.
        """
        self.log.info(
            "execute-request-start",
            _replace_msg="Starting execution of request: {request}",
            request=self.id,
        )
        try:
            attempt = Attempt()  # sets start time
            self.state = State.running
            self.save()
            with cd(self.dir):
                try:
                    self.activity.run()
                    attempt.record(self.activity)
                except Exception as e:
                    attempt.returncode = 70  # EX_SOFTWARE
                    attempt.stderr = str(e)
            self.attempts.append(attempt)
            self.state = evaluate_state(self.activity.returncode)
        except Exception:
            self.log.error(
                "execute-request-failed",
                _replace_msg="Executing request {request} failed. See exception for details.",
                request=self.id,
                exc_info=True,
            )
            self.state = State.error

        if self.state == State.error:
            self.log.info(
                "execute-request-finished-error",
                _replace_msg="Error executing request {request}.",
                request=self.id,
                stdout=attempt.stdout,
                stderr=attempt.stderr,
                duration=attempt.duration,
                returncode=attempt.returncode,
            )
        else:
            self.log.info(
                "execute-request-finished",
                _replace_msg="Executed request {request} (state: {state}).",
                request=self.id,
                state=self.state,
                duration=attempt.duration,
            )

        try:
            self.save()
        except Exception:
            # This was ignored before.
            # At least log what's happening here even if it's not critical.
            self.log.debug("execute-save-request-failed", exc_info=True)

    def update_due(self, due):
        """Sets next_due to a datetime object or ISO 8601 literal.

        Note that the next_due value must have tzinfo set. The request's
        state is updated according to the new due date. Returns True if
        the due date was effectively changed.
        """
        old = self.next_due
        if not due:
            self.next_due = None
        elif isinstance(due, datetime.datetime):
            self.next_due = due
        else:
            self.next_due = iso8601.parse_date(due)
        if self.next_due and not self.next_due.tzinfo:
            raise TypeError("next_due lacks time zone", self.next_due, self.id)
        self.update_state()
        return self.next_due != old

    def update_state(self):
        """Updates time-dependent request state."""
        if (
            self.state in (State.pending, State.postpone)
            and self.next_due
            and utcnow() >= self.next_due
        ):
            self.state = State.due
        if len(self.attempts) > self.MAX_RETRIES:
            self.state = State.retrylimit
        return self.state

    def other_requests(self):
        """Lists other requests currently active in the ReqManager."""
        return [
            r
            for r in self._reqmanager.requests.values()
            if r._reqid != self._reqid
        ]


def request_representer(dumper, data):
    # remove backlink before dumping a Request object
    d = copy.copy(data)
    if hasattr(d, "_reqmanager"):
        d._reqmanager = None
    return dumper.represent_object(d)


yaml.add_representer(Request, request_representer)


class Attempt:
    """Data object to track finished activities."""

    stdout = None
    stderr = None
    returncode = None
    finished = None
    duration = None

    def __init__(self):
        self.started = utcnow()

    def record(self, activity):
        """Logs activity outcomes so they may be overwritten later."""
        self.finished = utcnow()
        (self.stdout, self.stderr, self.returncode) = (
            activity.stdout,
            activity.stderr,
            activity.returncode,
        )
        if activity.duration:
            self.duration = activity.duration
        elif self.started and not self.duration:
            self.duration = (self.finished - self.started).total_seconds()
