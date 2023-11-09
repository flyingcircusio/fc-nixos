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
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import NamedTuple

import fc.maintenance.state
import fc.util.directory
import rich
import rich.syntax
import structlog
from fc.maintenance.activity import RebootType
from fc.util.checks import CheckResult
from fc.util.subprocess_helper import get_popen_stdout_lines
from fc.util.time_date import format_datetime, utcnow
from rich.table import Table

from . import state
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


class RequestsNotLoaded(Exception):
    def __init__(self):
        super().__init__(
            "Accessing requests is not possible because ReqManager has not been "
            "initialized."
        )


class PostponeMaintenance(Exception):
    pass


class TempfailMaintenance(Exception):
    pass


class HandleEnterExceptionResult(NamedTuple):
    exit: bool = False
    postpone: bool = False


class ReqManager:
    """
    Manage maintenance requests.
    The basic phases in the life of a request are:
    add, schedule, execute, archive.

    Requests may be merged when they are compatible with existing requests
    or postponed when they cannot be executed at the moment and should run at
    a later time.

    *Invasive* methods use `self.requests` and are allowed to make changes to
    requests. To use them, requests must be loaded and the global request
    manager lock must be held.

    These methods are typically used like this to handle locking and request
    loading:
    ```
    rm = ReqManager()
    with rm:
        rm.invasive_method()
    ```

    Invasive methods are:

    * scan
    * add
    * delete
    * schedule
    * update_states
    * execute
    * postpone
    * archive

    For non-invasive tasks, ReqManager methods can be used immediately. These
    include:

    * list_requests
    * show_request
    * check
    * get_metrics

    They also work with non-privileged users.
    """

    directory = None
    lockfile = None
    _requests: dict[str, Request] | None
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
        )
        self.spooldir = Path(spooldir)
        self.requestsdir = self.spooldir / "requests"
        self.archivedir = self.spooldir / "archive"
        self.last_run_stats_path = self.spooldir / "last_run.json"
        self.maintenance_marker_path = self.spooldir / "in_maintenance"
        self.enc_path = Path(enc_path)
        self.config_file = Path(config_file)
        self.config = configparser.ConfigParser()
        if self.config_file:
            if self.config_file.is_file():
                self.log.debug(
                    "reqmanager-enter-read-config",
                    config_file=str(config_file),
                )
                self.config.read(self.config_file)
            else:
                self.log.warn(
                    "reqmanager-enter-config-not-found",
                    config_file=str(config_file),
                )
        self.maintenance_preparation_seconds = int(
            self.config.get("maintenance", "preparation_seconds", fallback=300)
        )

    def __enter__(self):
        """
        Acquires global request manager lock and loads active requests.
        Must be called before using invasive methods that use
        `self.requests` and make changes to requests.

        Typically used like this:
        ```
        rm = ReqManager()
        with rm:
            rm.invasive_method()
        ```
        """
        for d in (self.spooldir, self.requestsdir, self.archivedir):
            if not d.exists():
                os.mkdir(d)

        if self.lockfile:
            return self
        self.lockfile = open(p.join(self.spooldir, ".lock"), "a+")
        fcntl.flock(self.lockfile.fileno(), fcntl.LOCK_EX)
        self.lockfile.seek(0)
        print(os.getpid(), file=self.lockfile)
        self.lockfile.flush()
        self.scan()
        return self

    def __exit__(self, exc_type, exc_value, exc_tb):
        if self.lockfile:
            self.lockfile.truncate(0)
            self.lockfile.close()
        self.lockfile = None

    def __rich__(self):
        requests = self._active_requests()
        table = Table(
            show_header=True,
            title="Maintenance requests",
            show_lines=True,
            title_style="bold",
        )

        if not requests:
            return "[bold]No maintenance requests at the moment.[/bold]"

        table.add_column("State")
        table.add_column("Req ID")
        table.add_column("Execution Time")
        table.add_column("Duration")
        table.add_column("Comment")
        table.add_column("Added")
        table.add_column("Updated")
        table.add_column("Scheduled")
        for req in sorted(requests):
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

    def _request_directory(self, request):
        """Return file system path for an active request."""
        return p.realpath(p.join(self.requestsdir, request.id))

    @property
    def requests(self):
        if self._requests is None:
            raise RequestsNotLoaded()

        return self._requests

    @require_lock
    def scan(self):
        self._requests = {}
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
        request.dir = self._request_directory(request)
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

    @require_lock
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
    def delete(self, reqid):
        """
        Deletes an active request from the queue.
        `reqid` can be a full request ID or a prefix.
        """
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

    @require_lock
    @require_directory
    def schedule(self):
        """Gets (updated) start times for pending requests from the directory."""
        self.log.debug("schedule-start")

        schedule_maintenance = {
            reqid: {
                "estimate": self._estimated_request_duration(req),
                "comment": req.comment,
            }
            for reqid, req in self.requests.items()
            if req.state == State.pending
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

    @require_lock
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
    def _enter_maintenance(self):
        """Enters maintenance mode which tells the directory to mark the machine
        as 'not in service'. The main reason is to avoid false alarms during expected
        service interruptions as the machine reboots or services are restarted.
        """
        self.log.debug("enter-maintenance")
        self.log.debug("mark-node-out-of-service")
        self.directory.mark_node_service_status(socket.gethostname(), False)

        if self.maintenance_marker_path.exists():
            previous_maintenance_entered_at = (
                self.maintenance_marker_path.read_text()
            )
            self.log.info(
                "enter-maintenance-marker-present",
                _replace_msg=(
                    "Maintenance marker is already present, likely from an "
                    "unfinished maintenance run. Keeping the old one from "
                    "{previous_maintenance_entered_at} and continuing."
                ),
                previous_maintenance_entered_at=previous_maintenance_entered_at,
            )
        else:
            self.maintenance_marker_path.write_text(utcnow().isoformat())
        postpone_seen = False
        tempfail_seen = False
        for name, command in self.config["maintenance-enter"].items():
            if not command.strip():
                continue

            log = self.log.bind(
                subsystem=name,
            )

            proc = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                shell=True,
                text=True,
            )
            log.info(
                "enter-maintenance-cmd",
                _replace_msg=(
                    "{subsystem}: Maintenance enter command started with PID "
                    "{cmd_pid}: `{command}`"
                ),
                command=command,
                cmd_pid=proc.pid,
            )

            stdout_lines = get_popen_stdout_lines(
                proc, log, "enter-maintenance-out"
            )
            stdout = "".join(stdout_lines)
            proc.wait()

            match proc.returncode:
                case 0:
                    log.debug("enter-maintenance-cmd-success")
                case state.EXIT_POSTPONE:
                    log.info(
                        "enter-maintenance-postpone",
                        command=command,
                        _replace_msg=(
                            "Command `{command}` requested to postpone all "
                            "requests."
                        ),
                    )
                    log.debug("enter-maintenance-postpone-out", stdout=stdout)
                    postpone_seen = True
                case state.EXIT_TEMPFAIL:
                    log.info(
                        "enter-maintenance-tempfail",
                        command=command,
                        _replace_msg=(
                            "Command `{command}` failed temporarily. "
                            "Requests should be tried again next time."
                        ),
                    )
                    log.debug("enter-maintenance-tempfail-out", stdout=stdout)
                    tempfail_seen = True
                case error:
                    log.error(
                        "enter-maintenance-fail",
                        command=command,
                        exit_code=error,
                    )
                    raise subprocess.CalledProcessError(error, command, stdout)

        if postpone_seen:
            raise PostponeMaintenance()

        if tempfail_seen:
            raise TempfailMaintenance()

    @require_directory
    def _leave_maintenance(self):
        """
        Tells the directory to mark the machine 'in service'.
        It's ok to call this method even when the machine is already in service.
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
        if self.maintenance_marker_path.exists():
            maintenance_entered_at = self.maintenance_marker_path.read_text()
            self.log.debug(
                "remove-maintenance-marker",
                maintenance_entered_at=maintenance_entered_at,
            )
            self.maintenance_marker_path.unlink()
        else:
            # Expected when `enter_maintenance` has not been called before.
            self.log.debug(
                "no-maintenance-marker",
                maintenance_marker_path=self.maintenance_marker_path,
            )

    def _runnable(self, run_all_now=False, force_run=False):
        """Generate due Requests in running order."""
        if run_all_now and force_run:
            self.log.warn(
                "execute-all-requests-now-force",
                _replace_msg=(
                    "Run-all mode with force requested. "
                    "Treating all requests as runnable."
                ),
            )
            runnable_requests = sorted(self.requests.values())
        elif run_all_now:
            self.log.warn(
                "execute-all-requests-now",
                _replace_msg=(
                    "Run all mode requested, treating pending requests as runnable."
                ),
            )
            runnable_requests = sorted(
                r
                for r in self.requests.values()
                if r.state in (State.pending, State.due, State.running)
            )
        else:
            # Normal operation
            runnable_requests = sorted(
                r
                for r in self.requests.values()
                if r.state in (State.due, State.running)
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
                    "command had a (temporary) failure. "
                    "Doing nothing unless --force-run is given, too."
                ),
            )
            return HandleEnterExceptionResult(exit=True)

        if not run_all_now and force_run:
            self.log.warn(
                "execute-requests-force",
                _replace_msg=(
                    "Due requests will be executed regardless of the "
                    "(temporary) failure of a maintenance enter command."
                ),
            )
            return HandleEnterExceptionResult()

        if run_all_now and force_run:
            self.log.warn(
                "run-all-now-force",
                _replace_msg=(
                    "Run all mode requested and force mode activated: "
                    "All requests will be executed now regardless of the "
                    "(temporary) failure of a maintenance enter command."
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

    def _reboot_and_exit(self, requested_reboots):
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
            subprocess.run(
                "reboot", check=True, capture_output=True, text=True
            )
            sys.exit(0)

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
        are ignored and requests are run regardless. This also runs requests in state
        'success' again when they are still in the queue after a recent system reboot.
        """
        self.log.debug(
            "execute-start", run_all_now=run_all_now, force_run=force_run
        )

        runnable_requests = self._runnable(run_all_now, force_run)
        if not runnable_requests:
            self._leave_maintenance()
            self._write_stats_for_execute()
            return

        prepare_dt = utcnow()
        try:
            self._enter_maintenance()
        except PostponeMaintenance:
            res = self._handle_enter_postpone(run_all_now, force_run)
            if res.postpone:
                for req in runnable_requests:
                    self.log.debug("execute-requests-postpone", request=req.id)
                    req.state = State.postpone
            if res.exit:
                self._leave_maintenance()
                self._write_stats_for_execute()
                return

        except TempfailMaintenance:
            res = self._handle_enter_tempfail(run_all_now, force_run)
            if res.exit:
                # Stay in maintenance mode as we expect the temporary failure
                # to go away on the next agent run.
                self._write_stats_for_execute()
                return

        except Exception:
            # Other exceptions are similar to tempfail, just with additional
            # logging. Could an error from a enter command, from the directory
            # or an internal one.
            self.log.error("execute-enter-maintenance-failed", exc_info=True)
            res = self._handle_enter_tempfail(run_all_now, force_run)
            if res.exit:
                # Might already be in maintenance or not, depending on where
                # _enter_maintenance failed. That's ok, the next agent
                # run can continue in either case.
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
        self._reboot_and_exit(requested_reboots)

        # When we are still here, no reboot happened. We can leave maintenance now.
        self.log.debug("no-reboot-requested")
        self._leave_maintenance()

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

    def _active_requests(self, req_id_prefix: str = "") -> list[Request]:
        """
        Loads active requests. Optionally, a request ID prefix can be passed
        for filtering.
        """
        name_matches = self.requestsdir.glob(req_id_prefix + "*")
        if name_matches:
            return sorted(
                [Request.load(name, self.log) for name in name_matches],
                key=lambda r: r.added_at
                or datetime.fromtimestamp(0, tz=timezone.utc),
            )
        return []

    def _archived_requests(self, req_id_prefix: str = "") -> list[Request]:
        """
        Loads archived requests by an request ID prefix. Optionally, a request
        ID prefix can be passed for filtering.
        """
        name_matches = self.archivedir.glob(req_id_prefix + "*")
        if name_matches:
            return sorted(
                [Request.load(name, self.log) for name in name_matches],
                key=lambda r: r.added_at
                or datetime.fromtimestamp(0, tz=timezone.utc),
            )
        return []

    def list_requests(self):
        rich.print(self)

    def show_request(self, request_id=None, dump_yaml=False):
        request_id_prefix = "" if request_id is None else request_id
        active_requests = self._active_requests(request_id_prefix)

        print()

        if request_id is None:
            # We only check active requests when no request ID was given.
            if not active_requests:
                rich.print(
                    "[bold]No active maintenance requests at the moment.[/bold]"
                )
                return

            if len(active_requests) == 1:
                rich.print(
                    "[bold]There's only one active request at the moment:[/bold]\n"
                )
            else:
                rich.print(
                    "[bold blue]Notice:[/bold blue] [bold]There are multiple "
                    "active requests, showing the newest one:[/bold]\n"
                )
            requests = active_requests
        else:
            # Request ID (prefix) was given. First, check active requests for
            # matches and use them, if present.
            if active_requests:
                if len(active_requests) > 1:
                    rich.print(
                        "[bold blue]Notice:[/bold blue] [bold]Found multiple "
                        f"active requests for prefix '{request_id}', showing "
                        "the newest:[/bold]\n"
                    )
                requests = active_requests
            else:
                # Nothing found in active requests, check archived requests.
                archived_requests = self._archived_requests(request_id_prefix)
                if len(archived_requests) == 1:
                    rich.print(
                        "[bold blue]Notice:[/bold blue] [bold]Found one "
                        f"archived request for prefix '{request_id}'\n"
                    )
                elif archived_requests:
                    rich.print(
                        "[bold blue]Notice:[/bold blue] [bold]Found multiple "
                        f"archived requests for prefix '{request_id}', showing "
                        "the newest:[/bold]\n"
                    )

                requests = archived_requests

            if not requests:
                rich.print(
                    f"[bold red]Error:[/bold red] [bold]Cannot locate any "
                    f"request with prefix '{request_id}'![/bold]"
                )
                return

        req = requests[-1]

        if dump_yaml:
            rich.print("\n[bold]Raw YAML serialization:[/bold]")
            yaml = Path(req.filename).read_text()
            rich.print(rich.syntax.Syntax(yaml, "yaml"))
        else:
            rich.print(req)

        if len(requests) > 1:
            other = ", ".join(req.id for req in requests[:-1])
            if request_id:
                rich.print(
                    "\n[bold blue]Notice:[/bold blue] Other matches with prefix "
                    f"'{request_id}': {other}"
                )
            else:
                rich.print(
                    f"\n[bold blue]Notice:[/bold blue] Other requests: {other}"
                )

    def check(self) -> CheckResult:
        errors = []
        warnings = []
        ok_info = []

        metrics = self.get_metrics()

        # Are we in maintenance mode? Check maintenance duration and add info
        # about the currently running request, if any.
        if maint_duration := metrics["in_maintenance_duration"]:
            # 15 minutes as estimate for total request run time is used here.
            # We could calculate it from the actual request estimates but it
            # wouldn't change much in reality and having a fixed value is
            # better for alerting, I think.
            # 20 minutes when maintenance_preparation_seconds is the default.
            maint_expected = self.maintenance_preparation_seconds + 15 * 60
            # 30 min, by default.
            maint_warning = maint_expected * 1.5
            # 60 min, by default.
            maint_critical = maint_warning * 2

            if maint_duration > maint_critical:
                target = errors
            elif maint_duration > maint_warning:
                target = warnings
            else:
                target = ok_info

            target.append(
                f"Maintenance mode activated {maint_duration} seconds ago."
            )

            if running_for_sec := metrics["request_running_for_seconds"]:
                target.append(
                    f"A maintenance request started {running_for_sec} "
                    "seconds ago."
                )
        else:
            ok_info.append("Machine is in service.")

        longest_in_queue_hours = (
            metrics["request_longest_in_queue_duration"] / 3600
        )
        # XXX: We probably want to get the lead time from the directory for a
        # better threshold.
        longest_in_queue_hours_warning = 7 * 24

        if longest_in_queue_hours > longest_in_queue_hours_warning:
            warnings.append(
                f"A maintenance request is in the queue for "
                f"{longest_in_queue_hours:.0f} hours."
            )

        if num_running := metrics["requests_running"]:
            # Test for some situations that look like a req manager bug.
            if num_running > 1:
                warnings.append(
                    f"{num_running} maintenance requests are running at the "
                    "moment. This should not happen in normal operation."
                )
            if not maint_duration:
                errors.append(
                    "A maintenance request is running but the system is not "
                    "in maintenance mode which is probably a ReqManager bug."
                )
            # Skip info about scheduled requests and those waiting to be scheduled
            # when we are currently running requests to avoid information
            # overload.
            return CheckResult(errors, warnings, ok_info)

        # ReqManager is not executing requests at the moment, add more info
        # about pending requests.
        if num_scheduled := metrics["requests_scheduled"]:
            next_due = format_datetime(
                datetime.fromtimestamp(
                    metrics["request_next_due_at"], tz=timezone.utc
                )
            )
            if num_scheduled == 1:
                ok_info.append(f"A maintenance request is due at {next_due}")
            else:
                ok_info.append(
                    f"{num_scheduled} scheduled maintenance requests. "
                    f"Next scheduled request is due at {next_due}."
                )

        if num_waiting_for_schedule := metrics[
            "requests_waiting_for_schedule"
        ]:
            if num_waiting_for_schedule == 1:
                ok_info.append(
                    f"A maintenance request is waiting to be scheduled."
                )
            else:
                ok_info.append(
                    f"{num_waiting_for_schedule} maintenance requests are "
                    "waiting to be scheduled."
                )

        return CheckResult(errors, warnings, ok_info)

    def get_metrics(self) -> dict:
        requests = self._active_requests()
        runnable = [
            r for r in requests if r.state in (State.due, State.running)
        ]

        metrics = {
            "name": "fc_maintenance",
            "requests_total": len(requests),
            "requests_runnable": len(runnable),
            # Initialize request stats. They will be overwritten if requests exist.
            "in_maintenance_duration": 0,
            "requests_tempfail": 0,
            "requests_postpone": 0,
            "requests_success": 0,
            "requests_error": 0,
            "requests_pending": 0,
            "requests_scheduled": 0,
            "requests_running": 0,
            "requests_waiting_for_schedule": 0,
            "request_longest_in_queue_duration": 0,
            "request_running_for_seconds": 0,
            "request_highest_retry_count": 0,
            "request_next_due_at": 0,
        }

        now = utcnow()

        if requests:
            requests_tempfail = []
            requests_error = []
            requests_postponed = []
            requests_success = []
            num_requests_pending = 0
            num_requests_running = 0
            num_requests_waiting_for_schedule = 0
            num_requests_scheduled = 0

            most_retries = 0
            oldest_added_at = requests[0].added_at
            oldest_next_due = None
            longest_running_seconds = 0

            for req in requests:
                most_retries = max(len(req.attempts), most_retries)
                oldest_added_at = min(oldest_added_at, req.added_at)

                match req.state:
                    case State.pending:
                        num_requests_pending += 1
                    case State.running:
                        # There should only be one but it's technically
                        # possible to have more than one in state 'running'.
                        num_requests_running += 1
                        if req.attempts:
                            longest_running_seconds = max(
                                longest_running_seconds,
                                (now - req.attempts[-1].started).seconds,
                            )

                if req.next_due:
                    num_requests_scheduled += 1
                    # Date can be in the past for requests that have already been tried,
                    # but that's ok.
                    oldest_next_due = (
                        min(req.next_due, oldest_next_due)
                        if oldest_next_due
                        else req.next_due
                    )
                else:
                    num_requests_waiting_for_schedule += 1

                if req.attempts:
                    match req.attempts[-1].returncode:
                        case None:
                            pass
                        case fc.maintenance.state.EXIT_TEMPFAIL:
                            requests_tempfail.append(req)
                        case fc.maintenance.state.EXIT_POSTPONE:
                            requests_postponed.append(req)
                        case 0:
                            requests_success.append(req)
                        case _error:
                            requests_error.append(req)

            metrics["requests_tempfail"] = len(requests_tempfail)
            metrics["requests_postpone"] = len(requests_postponed)
            metrics["requests_success"] = len(requests_success)
            metrics["requests_error"] = len(requests_error)
            metrics["requests_pending"] = num_requests_pending
            metrics["requests_running"] = num_requests_running
            metrics["requests_scheduled"] = num_requests_scheduled
            metrics[
                "requests_waiting_for_schedule"
            ] = num_requests_waiting_for_schedule

            metrics["request_longest_in_queue_duration"] = (
                now.timestamp() - oldest_added_at.timestamp()
            )
            metrics["request_highest_retry_count"] = most_retries
            metrics["request_running_for_seconds"] = longest_running_seconds

            if oldest_next_due:
                metrics["request_next_due_at"] = oldest_next_due.timestamp()

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

        if self.maintenance_marker_path.exists():
            maintenance_entered_at = datetime.fromisoformat(
                self.maintenance_marker_path.read_text()
            )

            metrics["in_maintenance_duration"] = (
                now - maintenance_entered_at
            ).seconds

        return metrics
