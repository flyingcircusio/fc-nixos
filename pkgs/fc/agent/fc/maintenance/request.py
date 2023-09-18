import contextlib
import copy
import datetime
import os
import os.path as p
import tempfile
from enum import Enum
from typing import Optional

import iso8601
import rich.table
import shortuuid
import structlog
import yaml
from fc.maintenance import state
from fc.util.time_date import ensure_timezone_present, format_datetime, utcnow

from .activity import Activity, ActivityMergeResult
from .estimate import Estimate
from .state import State, evaluate_state

_log = structlog.get_logger()


@contextlib.contextmanager
def cd(newdir):
    oldcwd = os.getcwd()
    os.chdir(newdir)
    try:
        yield
    finally:
        os.chdir(oldcwd)


class RequestMergeResult(Enum):
    NO_MERGE = 0
    REMOVE = 1
    UPDATE = 2
    SIGNIFICANT_UPDATE = 3


class Attempt:
    """Data object to track finished activities."""

    stdout: str | None = None
    stderr: str | None = None
    returncode: int | None = None
    finished: datetime.datetime | None = None
    duration: float | None = None

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


class Request:
    MAX_RETRIES = 48

    _comment: str | None
    _estimate: Estimate | None
    _reqid: str | None
    attempts: list[Attempt]
    activity: Activity
    added_at: datetime.datetime | None
    last_scheduled_at: datetime.datetime | None
    next_due: datetime.datetime | None
    state: State
    updated_at: datetime.datetime | None

    def __init__(
        self, activity, estimate=None, comment=None, dir=None, log=_log
    ):
        activity.request = self
        activity.set_up_logging(log)
        self.activity = activity
        self._estimate = Estimate(estimate) if estimate else None
        self._comment = comment
        self.dir = dir
        self.log = log
        self.attempts = []
        self._reqid = None  # will be set on first access
        self._reqmanager = None  # will be set in ReqManager
        self.added_at = None
        self.last_scheduled_at = None
        self.next_due = None
        self.state = State.pending
        self.updated_at = None

    @property
    def comment(self):
        if self._comment:
            return self._comment

        return self.activity.comment

    @property
    def estimate(self) -> Estimate:
        if self._estimate:
            return self._estimate

        return self.activity.estimate

    def __eq__(self, other):
        return self.__class__ == other.__class__ and self.id == other.id

    def __hash__(self):
        return hash(self.id)

    def __lt__(self, other):
        if self.next_due and other.next_due:
            return self.next_due < other.next_due
        elif self.next_due:
            return True
        elif other.next_due:
            return False
        elif self.added_at and other.added_at:
            return self.added_at < other.added_at
        else:
            return self.id < other.id

    def __rich__(self):
        table = rich.table.Table(show_header=False, show_lines=True)
        table.add_column()
        table.add_column()
        for key, val in self.__rich_repr__():
            table.add_row(key, val)
        return table

    def __rich_repr__(self):
        yield "ID", self._reqid
        yield "state", str(self.state)
        if self.next_due:
            yield "next_due", format_datetime(self.next_due)
        if self.added_at:
            yield "added_at", format_datetime(self.added_at)
        if self.updated_at:
            yield "updated_at", format_datetime(self.updated_at)
        if self.last_scheduled_at:
            yield "last_scheduled_at", format_datetime(self.last_scheduled_at)
        yield "estimate", str(self.estimate)
        yield "comment", self.comment
        yield "activity", self.activity
        yield "attempts", ", ".join(
            f"{format_datetime(a.finished)} (exit {a.returncode})"
            for a in self.attempts
        )

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

    @property
    def not_after(self) -> Optional[datetime.datetime]:
        if not self.next_due:
            return
        return self.next_due + datetime.timedelta(seconds=1800)

    @property
    def overdue(self) -> bool:
        if not self.not_after:
            return False
        return utcnow() > self.not_after

    @property
    def tempfail(self):
        return self.state not in state.ARCHIVE and self.attempts

    @classmethod
    def load(cls, dir, log):
        # need imports because such objects may be loaded via YAML
        import fc.maintenance.activity.reboot
        import fc.maintenance.activity.update
        import fc.maintenance.activity.vm_change
        import fc.maintenance.lib.reboot
        import fc.maintenance.lib.shellscript

        with open(p.join(dir, "request.yaml")) as f:
            instance = yaml.load(f, Loader=yaml.UnsafeLoader)

        instance.added_at = ensure_timezone_present(instance.added_at)
        # Some attributes are not present on legacy requests. For newer requests,
        # they are None after deserialization.
        if hasattr(instance, "next_due"):
            instance.next_due = ensure_timezone_present(instance.next_due)
        else:
            instance.next_due = None

        if hasattr(instance, "updated_at"):
            instance.updated_at = ensure_timezone_present(instance.updated_at)
        else:
            instance.updated_at = None

        if hasattr(instance, "last_scheduled_at"):
            instance.last_scheduled_at = ensure_timezone_present(
                instance.last_scheduled_at
            )
        else:
            instance.last_scheduled_at = None

        if not hasattr(instance, "_comment"):
            instance._comment = None

        if not hasattr(instance, "_estimate"):
            instance._estimate = None

        if not hasattr(instance, "state"):
            instance.state = State.pending

        instance.dir = dir
        instance.set_up_logging(log)

        with cd(dir):
            instance.activity.load()
            instance.activity.request = instance
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
            _replace_msg=(
                "Starting execution of request: {request} ({activity_type})"
            ),
            request=self.id,
            activity_type=self.activity.__class__.__name__,
        )
        attempt = Attempt()  # sets start time
        try:
            self.state = State.running
            self.attempts.append(attempt)
            self.save()
            with cd(self.dir):
                try:
                    self.activity.run()
                    attempt.record(self.activity)
                except Exception as e:
                    attempt.returncode = 70  # EX_SOFTWARE
                    attempt.stderr = str(e)
            self.state = evaluate_state(self.activity.returncode)
        except Exception:
            self.log.error(
                "execute-request-failed",
                _replace_msg=(
                    "Executing request {request} failed. See exception for "
                    "details."
                ),
                request=self.id,
                exc_info=True,
            )
            self.state = State.error

        self.log.info(
            "execute-request-finished",
            _replace_msg="Executed request {request} (state: {state}).",
            request=self.id,
            state=self.state,
            stdout=attempt.stdout,
            stderr=attempt.stderr,
            duration=attempt.duration,
            returncode=attempt.returncode,
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

    def update_state(self, due_dt=None):
        """Updates time-dependent request state."""
        self.log.debug("update-state", due_dt=format_datetime(due_dt))
        previous_state = self.state
        # We might be adjusting the state machine over time. We generally just
        # reset existing states and start fresh.
        if not State.valid_state(self.state):
            self.state = State.pending

        if self.state == State.postpone:
            self.state = State.pending

        if self.state == State.pending:
            if due_dt is None:
                due_dt = utcnow()
            if self.next_due and due_dt >= self.next_due:
                self.log.debug(
                    "request-update-state-due",
                    next_due=format_datetime(self.next_due),
                    due_dt=format_datetime(due_dt),
                )
                self.state = State.due

        if self.state == State.due:
            if len(self.attempts) > self.MAX_RETRIES:
                self.log.debug(
                    "request-update-state-retrylimit-hit",
                    limit=self.MAX_RETRIES,
                )
                self.state = State.error

            if self.overdue:
                self.state = State.postpone

        if previous_state != self.state:
            self.log.debug(
                "request-update-state-changed",
                previous=previous_state,
                state=self.state,
            )

    def merge(self, other):
        if not isinstance(other, Request):
            raise ValueError(
                f"Can only be merged with other Request instances! Given: {other}"
            )

        activity_merge_result = self.activity.merge(other.activity)
        assert isinstance(
            activity_merge_result, ActivityMergeResult
        ), f"{activity_merge_result} has wrong type, must be ActivityMergeResult"

        if not activity_merge_result.merged:
            return RequestMergeResult.NO_MERGE

        self.activity = activity_merge_result.merged

        # XXX: get rid of request estimate?
        if other._estimate:
            if not self._estimate:
                self._estimate = other._estimate
            else:
                self._estimate = max(self._estimate, other._estimate)
        if other._comment:
            if not self._comment:
                self._comment = other._comment
            elif self._comment != other._comment:
                self._comment += "\n\n" + other._comment

        if not activity_merge_result.is_effective:
            return RequestMergeResult.REMOVE

        self.log.debug(
            "request-merge-update",
            is_significant=activity_merge_result.is_significant,
            changes=activity_merge_result.changes,
            activity=activity_merge_result.merged,
        )
        self.updated_at = utcnow()
        self.save()

        if activity_merge_result.is_significant:
            return RequestMergeResult.SIGNIFICANT_UPDATE
        else:
            return RequestMergeResult.UPDATE

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

    if hasattr(d, "log"):
        del d.log

    return dumper.represent_object(d)


yaml.add_representer(Request, request_representer)
