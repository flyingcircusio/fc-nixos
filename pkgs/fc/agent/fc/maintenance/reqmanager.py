"""Manage maintenance requests."""

import configparser
import fcntl
import glob
import json
import os
import os.path as p
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

import fc.util.directory
import rich
import rich.syntax
import structlog
from fc.maintenance.activity import RebootType
from fc.util.time_date import format_datetime, utcnow
from rich.table import Table

from .request import Request, RequestMergeResult
from .state import ARCHIVE, State

DEFAULT_SPOOLDIR = "/var/spool/maintenance"
DEFAULT_CONFIG_FILE = "/etc/fc-agent.conf"

_log = structlog.get_logger()


def require_lock(func):
    """Decorator that asserts an open lockfile prior execution."""

    def assert_locked(self, *args, **kwargs):
        assert self.lockfile, "method {} required lock".format(func)
        return func(self, *args, **kwargs)

    return assert_locked


def require_directory(func):
    """Decorator that ensures a directory connection is present."""

    def with_directory_connection(self, *args, **kwargs):
        if self.directory is None:
            enc_data = None
            if self.enc_path:
                with open(self.enc_path) as f:
                    enc_data = json.load(f)
            self.directory = fc.util.directory.connect(enc_data)
        return func(self, *args, **kwargs)

    return with_directory_connection


class ReqManager:
    """Container for Requests."""

    directory = None
    lockfile = None
    requests: dict[str, Request]
    min_estimate_seconds: int = 900

    def __init__(
        self,
        spooldir,
        enc_path,
        config_file,
        log=_log,
    ):
        """Initialize ReqManager and create directories if necessary."""
        self.log = log
        self.log.debug(
            "reqmanager-init",
            spooldir=str(spooldir),
            enc_path=str(enc_path),
            config_file=str(config_file),
        )
        self.spooldir = Path(spooldir)
        self.requestsdir = self.spooldir / "requests"
        self.archivedir = self.spooldir / "archive"
        for d in (self.spooldir, self.requestsdir, self.archivedir):
            if not d.exists():
                os.mkdir(d)
        self.enc_path = Path(enc_path)
        self.config_file = Path(config_file)
        self.requests = {}

    def __enter__(self):
        if self.lockfile:
            return self
        self.lockfile = open(p.join(self.spooldir, ".lock"), "a+")
        fcntl.flock(self.lockfile.fileno(), fcntl.LOCK_EX)
        self.lockfile.seek(0)
        print(os.getpid(), file=self.lockfile)
        self.lockfile.flush()
        self.scan()
        self.config = configparser.ConfigParser()
        if self.config_file:
            if self.config_file.is_file():
                self.log.debug("reqmanager-enter-read-config")
                self.config.read(self.config_file)
            else:
                self.log.warn("reqmanager-enter-config-not-found")
        self.maintenance_preparation_seconds = int(
            self.config.get("maintenance", "preparation_seconds", fallback=300)
        )
        return self

    def __exit__(self, exc_type, exc_value, exc_tb):
        if self.lockfile:
            self.lockfile.truncate(0)
            self.lockfile.close()
        self.lockfile = None

    def __rich__(self):
        table = Table(
            show_header=True,
            title="Maintenance requests",
            show_lines=True,
            title_style="bold",
        )

        if not self.requests:
            return "[bold]No maintenance requests at the moment.[/bold]"

        table.add_column("State")
        table.add_column("Req ID")
        table.add_column("Execution Time")
        table.add_column("Duration")
        table.add_column("Comment")
        table.add_column("Added")
        table.add_column("Updated")
        table.add_column("Scheduled")
        for req in sorted(self.requests.values()):
            if req.next_due:
                exec_interval = (
                    format_datetime(req.next_due)
                    + " -\n"
                    + format_datetime(req.not_after)
                )

                if req.overdue:
                    exec_interval += " (overdue)"
            else:
                exec_interval = "--- TBA ---"

            table.add_row(
                f"{req.state} ({len(req.attempts)}/{req.MAX_RETRIES})",
                req.id[:6],
                exec_interval,
                str(req.estimate),
                req.comment,
                format_datetime(req.added_at) if req.added_at else "-",
                format_datetime(req.updated_at) if req.updated_at else "-",
                format_datetime(req.last_scheduled_at)
                if req.last_scheduled_at
                else "-",
            )

        return table

    def dir(self, request):
        """Return file system path for request identified by `reqid`."""
        return p.realpath(p.join(self.requestsdir, request.id))

    def scan(self):
        self.requests = {}
        for d in glob.glob(p.join(self.requestsdir, "*")):
            if not p.isdir(d):
                continue
            try:
                req = Request.load(d, self.log)
                req._reqmanager = self
                self.requests[req.id] = req
            except Exception as exc:
                with open(p.join(d, "_load_request_yaml_error"), "a") as f:
                    print(exc, file=f)
                self.log.error(
                    "request-load-error",
                    _replace_msg=(
                        "Loading {request} failed, archiving request. See "
                        "exception for details."
                    ),
                    request=p.basename(d),
                    exc_info=True,
                )
                os.rename(d, p.join(self.archivedir, p.basename(d)))

    def _add_request(self, request: Request):
        self.requests[request.id] = request
        request.dir = self.dir(request)
        request._reqmanager = self
        request.added_at = utcnow()
        request.save()
        self.log.info(
            "request-added",
            _replace_msg="Added request: {request}",
            request=request.id,
            comment=request.comment,
        )
        return request

    def _merge_request(
        self, existing_request: Request, request: Request
    ) -> RequestMergeResult:
        merge_result = existing_request.merge(request)
        match merge_result:
            case RequestMergeResult.UPDATE:
                self.log.info(
                    "requestmanager-merge-update",
                    _replace_msg=(
                        "New request {request} was merged with an "
                        "existing request {merged}."
                    ),
                    request=request.id,
                    merged=existing_request.id,
                )
                existing_request.updated_at = utcnow()
                existing_request.save()
                # Run schedule_maintenance to update the comment.
                # Schedule all requests to keep the order.
                self.schedule()

            case RequestMergeResult.SIGNIFICANT_UPDATE:
                self.log.info(
                    "requestmanager-merge-significant",
                    _replace_msg=(
                        "New request {request} was merged with an "
                        "existing request {merged}. Change is "
                        "significant so execution will be postponed."
                    ),
                    request=request.id,
                    merged=existing_request.id,
                )
                # Run schedule to update the comment and duration estimate.
                # Schedule all requests to keep the order.
                self.schedule()
                # XXX: This triggers sending an email to technical contacts
                # to inform them about a significant change to an existing activity.
                # The postpone interval here (8 hours) is a bit arbitrary and the idea
                # is that there should be enough time to inform users before executing
                # the updated request. The need for postponing should be determined
                # by the directory instead.
                postpone_maintenance = {
                    existing_request.id: {"postpone_by": 8 * 60 * 60}
                }
                self.log.debug(
                    "postpone-maintenance-directory", args=postpone_maintenance
                )
                self.directory.postpone_maintenance(postpone_maintenance)
                existing_request.updated_at = utcnow()
                existing_request.save()

            case RequestMergeResult.REMOVE:
                self.log.info(
                    "requestmanager-merge-remove",
                    _replace_msg=(
                        "New request {request} was merged with an "
                        "existing request {merged} and produced a "
                        "no-op request. Removing the request."
                    ),
                    request=request.id,
                    merged=existing_request.id,
                )
                self.delete(existing_request.id)

            case RequestMergeResult.NO_MERGE:
                self.log.debug(
                    "requestmanager-merge-skip",
                    existing_request=existing_request.id,
                    new_request=request.id,
                )

        return merge_result

    def add(self, request: Request | None, add_always=False) -> Request | None:
        """Adds a Request object to the local queue.
        New request is merged with existing requests. If the merge results
        in a no-op request, the existing request is deleted.

        A request is only added if the activity is effective, unless add_always is given.
        Setting `add_always` skips request merging and the effectiveness check.

        Returns Request object, new or merged
        None if not added/no-op.
        """
        self.log.debug("request-add-start", request_object=request)

        if request is None:
            self.log.debug("request-add-no-request")
            return

        if add_always:
            self.log.debug("request-add-always", request=request.id)
            return self._add_request(request)

        for existing_request in reversed(self.requests.values()):
            # We can stop if request was merged or removed, continue otherwise
            match self._merge_request(existing_request, request):
                case RequestMergeResult.SIGNIFICANT_UPDATE | RequestMergeResult.UPDATE:
                    return existing_request
                case RequestMergeResult.REMOVE:
                    return
                case RequestMergeResult.NO_MERGE:
                    pass

        if not request.activity.is_effective:
            self.log.info(
                "request-skip",
                _replace_msg=(
                    "Activity for {request} wouldn't apply any changes. Nothing added."
                ),
                request=request.id,
            )
            return

        return self._add_request(request)

    def _estimated_request_duration(self, request) -> int:
        return max(
            self.min_estimate_seconds,
            int(request.estimate) + self.maintenance_preparation_seconds,
        )

    @require_lock
    @require_directory
    def schedule(self):
        """Triggers request scheduling on server."""
        self.log.debug("schedule-start")

        schedule_maintenance = {
            reqid: {
                "estimate": self._estimated_request_duration(req),
                "comment": req.comment,
            }
            for reqid, req in self.requests.items()
        }
        if schedule_maintenance:
            self.log.debug(
                "schedule-maintenances",
                request_count=len(schedule_maintenance),
                requests=list(schedule_maintenance),
            )

        result = self.directory.schedule_maintenance(schedule_maintenance)
        disappeared = set()
        for key, val in result.items():
            try:
                req = self.requests[key]
                due_changed = req.update_due(val["time"])
                self.log.debug(
                    "schedule-request-result",
                    request=key,
                    data=val,
                    due_changed=due_changed,
                )
                if due_changed:
                    self.log.info(
                        "schedule-change-start-time",
                        _replace_msg=(
                            "Changing start time of {request} to {at}."
                        ),
                        request=req.id,
                        at=val["time"],
                    )
                    req.last_scheduled_at = utcnow()
                    req.save()
            except KeyError:
                self.log.warning(
                    "schedule-request-disappeared",
                    _replace_msg=(
                        "Request {request} disappeared, marking as deleted."
                    ),
                    request=key,
                )
                disappeared.add(key)
        if disappeared:
            self.directory.end_maintenance(
                {key: {"result": "deleted"} for key in disappeared}
            )

    def runnable(self, run_all_now: bool):
        """Generate due Requests in running order."""
        if run_all_now:
            self.log.warn(
                "execute-all-requests-now",
                _replace_msg=(
                    "Run all mode requested, treating all requests as runnable."
                ),
            )
            runnable_requests = sorted(self.requests.values())

        else:
            runnable_requests = sorted(
                r for r in self.requests.values() if r.state == State.due
            )

        if not runnable_requests:
            self.log.info(
                "runnable-requests-empty",
                _replace_msg="No runnable maintenance requests.",
            )
            return runnable_requests

        runnable_count = len(runnable_requests)

        if runnable_count == 1:
            msg = "Executing one runnable maintenance request."
        else:
            msg = "Executing {runnable_count} runnable maintenance requests."

        self.log.info(
            "runnable-requests",
            _replace_msg=msg,
            runnable_count=runnable_count,
        )

        return runnable_requests

    def enter_maintenance(self):
        """Set this node in 'temporary maintenance' mode."""
        self.log.debug("enter-maintenance")
        self.log.debug("mark-node-out-of-service")
        self.directory.mark_node_service_status(socket.gethostname(), False)
        for name, command in self.config["maintenance-enter"].items():
            if not command.strip():
                continue
            self.log.info(
                "enter-maintenance-subsystem", subsystem=name, command=command
            )
            subprocess.run(command, shell=True, check=True)

    def leave_maintenance(self):
        self.log.debug("leave-maintenance")
        for name, command in self.config["maintenance-leave"].items():
            if not command.strip():
                continue
            self.log.info(
                "leave-maintenance-subsystem", subsystem=name, command=command
            )
            subprocess.run(command, shell=True, check=True)
        self.log.debug("mark-node-in-service")
        self.directory.mark_node_service_status(socket.gethostname(), True)

    def update_states(self):
        """
        Updates all request states.

        We want to run continuously scheduled requests in one go to reduce overall
        maintenance time and reboots.

        A Request is considered "due" if its start time is in the past or is
        scheduled directly after a previous due request.

        In other words: if there's a due request, following requests can be run even if
        their start time is not reached, yet.
        """
        due_dt = utcnow()
        requests = self.requests.values()
        self.log.debug("update-states-start", request_count=len(requests))
        for request in sorted(requests):
            request.update_state(due_dt)
            request.save()
            if request.state == State.due and request.next_due:
                delta = timedelta(
                    seconds=self._estimated_request_duration(request) + 60
                )
                due_dt = max(utcnow(), request.next_due + delta)

    @require_directory
    @require_lock
    def execute(self, run_all_now: bool = False):
        """
        Enters maintenance mode, executes requests and reboots if activities request it.

        In normal operation, due requests are run in the order of their scheduled start
        time.

        When `run_all_now` is given, all requests are run regardless of their scheduled
        time but still in order.
        """

        runnable_requests = self.runnable(run_all_now)
        if not runnable_requests:
            self.leave_maintenance()
            return

        requested_reboots = set()
        self.enter_maintenance()
        for req in runnable_requests:
            req.execute()
            if req.state == State.success:
                requested_reboots.add(req.activity.reboot_needed)

        # Execute any reboots while still in maintenance.
        self.reboot_and_exit(requested_reboots)

        # When we are still here, no reboot happened. We can leave maintenance now.
        self.log.debug("no-reboot-requested")
        self.leave_maintenance()

    @require_lock
    @require_directory
    def postpone(self):
        """Instructs directory to postpone requests.

        Postponed requests get their new scheduled time with the next
        schedule call.
        """
        self.log.debug("postpone-start")
        postponed = [
            r for r in self.requests.values() if r.state == State.postpone
        ]
        if not postponed:
            return
        postpone_maintenance = {
            req.id: {"postpone_by": 2 * int(req.estimate)} for req in postponed
        }
        self.log.debug(
            "postpone-maintenance-directory", args=postpone_maintenance
        )
        # This directory call just returns an empty string.
        self.directory.postpone_maintenance(postpone_maintenance)
        for req in postponed:
            # Resetting the due datetime also sets the state to pending.
            # Request will be rescheduled on the next run.
            req.update_due(None)
            req.save()

    @require_lock
    @require_directory
    def archive(self):
        """Move all completed requests to archivedir."""
        self.log.debug("archive-start")
        archived = [r for r in self.requests.values() if r.state in ARCHIVE]
        if not archived:
            return
        end_maintenance = {
            req.id: {
                "duration": req.duration,
                "result": str(req.state),
                "comment": req.comment,
                "estimate": self._estimated_request_duration(req),
            }
            for req in archived
        }
        self.log.debug(
            "archive-end-maintenance-directory", args=end_maintenance
        )
        self.directory.end_maintenance(end_maintenance)
        for req in archived:
            self.log.info(
                "archive-request",
                _replace_msg="Request {request} completed, archiving request.",
                request=req.id,
            )
            dest = p.join(self.archivedir, req.id)
            os.rename(req.dir, dest)
            req.dir = dest
            req.save()

    @require_lock
    def list(self):
        rich.print(self)

    @require_lock
    def show(self, request_id=None, dump_yaml=False):
        if not self.requests:
            rich.print("[bold]No maintenance requests at the moment.[/bold]")
            return

        if request_id is None:
            requests = list(self.requests.values())
            if len(self.requests) == 1:
                rich.print("[bold]There's only one at the moment:[/bold]\n")
        else:
            requests = sorted(
                [
                    req
                    for key, req in self.requests.items()
                    if key.startswith(request_id)
                ],
                key=lambda r: r.added_at or datetime.fromtimestamp(0),
            )
            if not requests:
                rich.print(
                    f"[bold red]Error:[/bold red] [bold]Cannot locate any "
                    f"request with prefix '{request_id}'![/bold]"
                )
                return

        if len(requests) > 1:
            rich.print(
                "[bold blue]Notice:[/bold blue] [bold]Multiple requests "
                "found, showing the newest:[/bold]\n"
            )

        req = requests[-1]

        if dump_yaml:
            rich.print("\n[bold]Raw YAML serialization:[/bold]")
            yaml = Path(req.filename).read_text()
            rich.print(rich.syntax.Syntax(yaml, "yaml"))
        else:
            rich.print(req)

    @require_lock
    def delete(self, reqid):
        self.log.debug("delete-start", request=reqid)
        req = None
        for i in self.requests:
            if i.startswith(reqid):
                req = self.requests[i]
                break
        if not req:
            self.log.warning(
                "delete-skip-missing",
                _replace_msg="Cannot locate request {request}, skipping.",
                request=reqid,
            )
            return
        req.state = State.deleted
        req.save()
        self.log.info(
            "delete-finished",
            _replace_msg="Marked request {request} as deleted.",
            request=req.id,
        )

    def reboot_and_exit(self, requested_reboots):
        if RebootType.COLD in requested_reboots:
            self.log.info(
                "maintenance-poweroff",
                _replace_msg=(
                    "Doing a cold boot in five seconds to finish maintenance "
                    "activities."
                ),
            )
            time.sleep(5)
            subprocess.run(
                "poweroff", check=True, capture_output=True, text=True
            )
            sys.exit(0)

        elif RebootType.WARM in requested_reboots:
            self.log.info(
                "maintenance-reboot",
                _replace_msg=(
                    "Rebooting in five seconds to finish maintenance "
                    "activities."
                ),
            )
            time.sleep(5)
            subprocess.run("reboot", check=True, capture_output=True, text=True)
            sys.exit(0)
