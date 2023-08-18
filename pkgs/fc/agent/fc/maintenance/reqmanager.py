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
from typing import NamedTuple

import fc.maintenance.state
import fc.util.directory
import rich
import rich.syntax
import structlog
from fc.maintenance.activity import RebootType
from fc.util.time_date import format_datetime, utcnow
from rich.table import Table

from .request import Request, RequestMergeResult
from .state import ARCHIVE, EXIT_POSTPONE, EXIT_TEMPFAIL, State

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


class PostponeMaintenance(Exception):
    pass


class TempfailMaintenance(Exception):
    pass


class HandleEnterExceptionResult(NamedTuple):
    exit: bool = False
    postpone: bool = False


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
        self.last_run_stats_path = self.spooldir / "last_run.json"
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

    def runnable(self, run_all_now=False):
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

    @require_lock
    @require_directory
    def enter_maintenance(self):
        """Enters maintenance mode which tells the directory to mark the machine
        as 'not in service'. The main reason is to avoid false alarms during expected
        service interruptions as the machine reboots or services are restarted.
        """
        self.log.debug("enter-maintenance")
        self.log.debug("mark-node-out-of-service")
        self.directory.mark_node_service_status(socket.gethostname(), False)
        postpone_seen = False
        tempfail_seen = False
        for name, command in self.config["maintenance-enter"].items():
            if not command.strip():
                continue
            self.log.info(
                "enter-maintenance-subsystem", subsystem=name, command=command
            )
            try:
                subprocess.run(command, shell=True, check=True)
            except subprocess.CalledProcessError as e:
                if e.returncode == EXIT_POSTPONE:
                    self.log.info(
                        "enter-maintenance-postpone",
                        command=command,
                        _replace_msg=(
                            "Command `{command}` requested to postpone all requests."
                        ),
                    )
                    postpone_seen = True
                elif e.returncode == EXIT_TEMPFAIL:
                    self.log.info(
                        "enter-maintenance-tempfail",
                        command=command,
                        _replace_msg=(
                            "Command `{command}` failed temporarily."
                            "Requests should be tried again next time."
                        ),
                    )
                    tempfail_seen = True
                else:
                    raise

        if postpone_seen:
            raise PostponeMaintenance()

        if tempfail_seen:
            raise TempfailMaintenance()

    @require_lock
    @require_directory
    def leave_maintenance(self):
        """
        Tells the directory to mark the machine 'in service'.
        """
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

    def _handle_enter_postpone(
        self, run_all_now: bool, force_run: bool
    ) -> HandleEnterExceptionResult:
        """
        We have to handle 4 possible flag combinations of --run-all-now
        and --force-run, which are used interactively. In normal
        operation, both are false and we mark runnable requests for
        postponing, leave maintenance and stop execution.
        """
        if not run_all_now and not force_run:
            # Normal operation.
            return HandleEnterExceptionResult(postpone=True, exit=True)

        if run_all_now and not force_run:
            self.log.info(
                "run-all-now-postponed",
                _replace_msg=(
                    "Run all mode requested but a maintenance enter "
                    "command requested to postpone the activities. Doing "
                    "nothing unless --force-run is given, too."
                ),
            )
            return HandleEnterExceptionResult(exit=True)

        if not run_all_now and force_run:
            self.log.warn(
                "execute-requests-force",
                _replace_msg=(
                    "Force mode activated: Activities will be executed "
                    "regardless of the postpone request."
                ),
            )
            return HandleEnterExceptionResult()

        if run_all_now and force_run:
            self.log.warn(
                "run-all-now-force",
                _replace_msg=(
                    "Run all mode requested and force mode activated: "
                    "Activities will be executed regardless of the "
                    "postpone request."
                ),
            )
            return HandleEnterExceptionResult()

    def _handle_enter_tempfail(
        self, run_all_now: bool, force_run: bool
    ) -> HandleEnterExceptionResult:
        if not run_all_now and not force_run:
            # Normal operation.
            self.log.debug(
                "execute-requests-tempfail",
            )
            # We stay in maintenance and try again on the next run.
            return HandleEnterExceptionResult(exit=True)

        if run_all_now and not force_run:
            self.log.info(
                "run-all-now-tempfail",
                _replace_msg=(
                    "Run all mode requested but a maintenance enter "
                    "command had a temporary failure."
                    "Doing nothing unless --force-run is given, too."
                ),
            )
            return HandleEnterExceptionResult(exit=True)

        if not run_all_now and force_run:
            self.log.warn(
                "execute-requests-force",
                _replace_msg=(
                    "Due requests will be executed regardless of the temporary failure "
                    "of a maintenance enter command."
                ),
            )
            return HandleEnterExceptionResult()

        if run_all_now and force_run:
            self.log.warn(
                "run-all-now-force",
                _replace_msg=(
                    "Run all mode requested and force mode activated: "
                    "All requests will be executed now regardless of the temporary "
                    "failure of a maintenance enter command."
                ),
            )
            return HandleEnterExceptionResult()

    def _write_stats_for_execute(
        self,
        prepare_dt: datetime | None = None,
        exec_dt: datetime | None = None,
        runnable_requests: list[Request] | None = None,
        reboot_requested=False,
    ):
        now = utcnow()
        if runnable_requests is None:
            runnable_requests = []

        stats = {
            "prepare_duration": 0,
            "exec_duration": 0,
            "finished_at": now.isoformat(),
            "reboot": reboot_requested,
            "executed_requests": len(runnable_requests),
            "request_states": {r.id: str(r.state) for r in runnable_requests},
        }

        if exec_dt and prepare_dt:
            stats["prepare_duration"] = (exec_dt - prepare_dt).seconds
            stats["exec_duration"] = (now - exec_dt).seconds

        self.log.debug("execute-stats", **stats)

        with open(self.last_run_stats_path, "w") as wf:
            json.dump(stats, wf, indent=4)

    @require_directory
    @require_lock
    def execute(self, run_all_now: bool = False, force_run: bool = False):
        """
        Enters maintenance mode, executes requests and reboots if activities request it.

        In normal operation, due requests are run in the order of their scheduled start
        time.

        After entering maintenance mode, but before executing requests,
        maintenance enter commands defined in the agent config file are executed.
        These commands can request to leave maintenance mode and find a new scheduled
        time (EXIT_POSTPONE) or stay in maintenance mode and try again on the next
        maintenance run (EXIT_TEMPFAIL).

        When `run_all_now` is given, all requests are run regardless of their scheduled
        time but still in order. Postpone and tempfail from maintenance enter commands
        are still respected so requests may actually not run.

        When `force_run` is given, postpone and tempfail from maintenance enter command
        are ignored and requests are run regardless. WARNING: this can be dangerous!
        """

        runnable_requests = self.runnable(run_all_now)
        if not runnable_requests:
            self.leave_maintenance()
            self._write_stats_for_execute()
            return

        prepare_dt = utcnow()
        try:
            self.enter_maintenance()
        except PostponeMaintenance:
            res = self._handle_enter_postpone(run_all_now, force_run)
            if res.postpone:
                for req in runnable_requests:
                    self.log.debug("execute-requests-postpone", request=req.id)
                    req.state = State.postpone
            if res.exit:
                self.leave_maintenance()
                self._write_stats_for_execute()
                return

        except TempfailMaintenance:
            res = self._handle_enter_tempfail(run_all_now, force_run)
            if res.exit:
                # Stay in maintenance mode.
                self._write_stats_for_execute()
                return

        # We are now in maintenance mode, start the action.
        requested_reboots = set()
        exec_dt = utcnow()
        for req in runnable_requests:
            req.execute()
            if req.state == State.success:
                requested_reboots.add(req.activity.reboot_needed)

        self._write_stats_for_execute(
            prepare_dt, exec_dt, runnable_requests, bool(requested_reboots)
        )

        # Execute any reboots while still in maintenance mode.
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

    def get_metrics(self) -> dict:
        requests = sorted(self.requests.values())
        runnable = self.runnable()

        metrics = {
            "name": "fc_maintenance",
            "requests_total": len(requests),
            "requests_runnable": len(runnable),
            # Initialize request stats. They will be overwritten if requests exist.
            "requests_tempfail": 0,
            "requests_postpone": 0,
            "requests_success": 0,
            "requests_error": 0,
            "request_longest_in_queue_seconds": 0,
            "request_highest_retry_count": 0,
        }

        now = utcnow()

        if requests:
            requests_tempfail = []
            requests_error = []
            requests_postponed = []
            requests_success = []

            most_retries = 0
            oldest_added_at = requests[0].added_at

            for req in requests:
                most_retries = max(len(req.attempts), most_retries)
                oldest_added_at = min(oldest_added_at, req.added_at)

                if req.attempts:
                    match req.attempts[-1].returncode:
                        case fc.maintenance.state.EXIT_TEMPFAIL:
                            requests_tempfail.append(req)
                        case fc.maintenance.state.EXIT_POSTPONE:
                            requests_postponed.append(req)
                        case 0:
                            requests_success.append(req)
                        case error:
                            requests_error.append(req)

            metrics["requests_tempfail"] = len(requests_tempfail)
            metrics["requests_postpone"] = len(requests_postponed)
            metrics["requests_success"] = len(requests_success)
            metrics["requests_error"] = len(requests_error)

            metrics["request_longest_in_queue_duration"] = (
                now.timestamp() - oldest_added_at.timestamp()
            )

            metrics["request_highest_retry_count"] = most_retries

        # We expect the last run stats file to be present at all times except on
        # new machines that haven't run execute() yet.
        if self.last_run_stats_path.exists():
            with self.last_run_stats_path.open() as f:
                last_run_stats = json.load(f)

            metrics["last_run_prepare_duration"] = last_run_stats[
                "prepare_duration"
            ]
            metrics["last_run_exec_duration"] = last_run_stats["exec_duration"]
            metrics["last_run_finished_seconds_ago"] = (
                now - datetime.fromisoformat(last_run_stats["finished_at"])
            ).seconds

        return metrics
