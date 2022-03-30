"""Manage maintenance requests."""

import argparse
import configparser
import fcntl
import glob
import json
import os
import os.path as p
import socket
import subprocess
from datetime import datetime
from pathlib import Path

import fc.util.directory
import rich
import rich.syntax
import structlog
from fc.maintenance.activity import RebootType
from fc.util.logging import init_logging
from fc.util.time_date import format_datetime, utcnow
from rich.table import Table

from .request import Request
from .state import ARCHIVE, State

DEFAULT_DIR = "/var/spool/maintenance"

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

    TIMEFMT = "%Y-%m-%d %H:%M:%S %Z"

    directory = None
    lockfile = None

    def __init__(
        self, spooldir=DEFAULT_DIR, enc_path=None, config_file=None, log=_log
    ):
        """Initialize ReqManager and create directories if necessary."""
        self.spooldir = spooldir
        self.requestsdir = p.join(self.spooldir, "requests")
        self.archivedir = p.join(self.spooldir, "archive")
        for d in (self.spooldir, self.requestsdir, self.archivedir):
            if not p.exists(d):
                os.mkdir(d)
        self.enc_path = enc_path
        self.config_file = config_file
        self.log = log
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
            self.config.read(self.config_file)
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
        table.add_column("Request ID")
        table.add_column("Execution Time")
        table.add_column("Duration")
        table.add_column("Comment")
        table.add_column("Added")
        table.add_column("Last Scheduled")
        for req in sorted(self.requests.values()):
            table.add_row(
                str(req.state),
                req.id,
                format_datetime(req.next_due)
                if req.next_due
                else "--- TBA ---",
                str(req.estimate),
                req.comment,
                format_datetime(req.added_at) if req.added_at else "-",
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
                    _replace_msg="Loading {request} failed, archiving request. See exception for details.",
                    request=p.basename(d),
                    exc_info=True,
                )
                os.rename(d, p.join(self.archivedir, p.basename(d)))

    def add(self, request, skip_same_comment=True):
        """Adds a Request object to the local queue.

        If skip_same_comment is True, a request is not added if a
        requests with the same comment already exists in the queue.

        Returns modified Request object or None if nothing was added.
        """
        if skip_same_comment and request.comment:
            duplicate = self.find_by_comment(request.comment)
            if duplicate:
                self.log.info(
                    "request-skip-duplicate",
                    _replace_msg="When adding {request}, found identical request {duplicate}. Nothing added.",
                    request=request.id,
                    duplicate=duplicate.id,
                )
                return None
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

    def find_by_comment(self, comment):
        """Returns first request with `comment` or None."""
        for r in self.requests.values():
            if r.comment == comment:
                return r

    @require_lock
    @require_directory
    def schedule(self):
        """Triggers request scheduling on server."""
        self.log.debug("schedule-start")
        schedule_maintenance = {
            reqid: {"estimate": int(req.estimate), "comment": req.comment}
            for reqid, req in self.requests.items()
        }
        if schedule_maintenance:
            self.log.debug(
                "schedule-maintenances", request_count=len(schedule_maintenance)
            )

        result = self.directory.schedule_maintenance(schedule_maintenance)
        disappeared = set()
        for key, val in result.items():
            try:
                req = self.requests[key]
                self.log.debug("schedule-request", request=key, data=val)
                if req.update_due(val["time"]):
                    self.log.info(
                        "schedule-change-start-time",
                        _replace_msg="Changing start time of {request} to {at}",
                        request=req.id,
                        at=val["time"],
                    )
                    req.last_scheduled_at = utcnow()
                    req.save()
            except KeyError:
                self.log.warning(
                    "schedule-request-disappeared",
                    _replace_msg="Request {request} disappeared, marking as deleted.",
                    request=key,
                )
                disappeared.add(key)
        if disappeared:
            self.directory.end_maintenance(
                {key: {"result": "deleted"} for key in disappeared}
            )

    def runnable(self):
        """Generate due Requests in running order."""
        requests = []
        for request in self.requests.values():
            new_state = request.update_state()
            if new_state is State.running:
                yield request
            elif new_state in (State.due, State.tempfail):
                requests.append(request)
        yield from sorted(requests)

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

    @require_directory
    @require_lock
    def execute(self, run_all_now=False):
        """Process maintenance requests.

        If there is an already active request, run to termination first.
        After that, select the oldest due request as next active request.
        """
        if run_all_now:
            self.log.warn(
                "execute-all-requests-now",
                _replace_msg="Run all mode requested, treating all requests as runnable.",
            )
            runnable_requests = list(self.requests.values())
        else:
            runnable_requests = list(self.runnable())

        if not runnable_requests:
            self.log.info(
                "execute-requests-empty",
                _replace_msg="No runnable maintenance requests.",
            )
            self.leave_maintenance()
            return

        runnable_count = len(runnable_requests)
        if runnable_count == 1:
            msg = "Executing one runnable maintenance request."
        else:
            msg = "Executing {runnable_count} runnable maintenance requests."
        self.log.info(
            "execute-requests-runnable",
            _replace_msg=msg,
            runnable_count=runnable_count,
        )

        requested_reboots = set()
        self.enter_maintenance()
        for req in runnable_requests:
            req.execute()
            if req.state == State.success:
                requested_reboots.add(req.activity.reboot_needed)

        # Execute any reboots while still in maintenance.
        # Using the 'if' with the side effect has been a huge problem
        # WRT to readability for me when trying to find out whether it
        # is safe to call 'leave_maintenance' in the except: part a few
        # lines below.
        if not self.reboot(requested_reboots):
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
        self.directory.postpone_maintenance(postpone_maintenance)
        for req in postponed:
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
            req.id: {"duration": req.duration, "result": str(req.state)}
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

        rich.print(req)

        if dump_yaml:
            rich.print("\n[bold]Raw YAML serialization:[/bold]")
            yaml = Path(req.filename).read_text()
            rich.print(rich.syntax.Syntax(yaml, "yaml"))

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
                _replace_msg="Cannot locate request {request}, skipping",
                request=reqid,
            )
            return
        req.state = State.deleted
        req.save()
        self.log.info(
            "delete-finished",
            _replace_msg="Marked request {request} as deleted",
            request=req.id,
        )

    def reboot(self, requested_reboots):
        if RebootType.COLD in requested_reboots:
            self.log.info(
                "maintenance-poweroff",
                _replace="Doing a cold boot now to finish maintenance activities.",
            )
            subprocess.run(
                "poweroff", check=True, capture_output=True, text=True
            )
            return True
        elif RebootType.WARM in requested_reboots:
            self.log.info(
                "maintenance-reboot",
                _replace_msg="Rebooting now to finish maintenance activities.",
            )
            subprocess.run("reboot", check=True, capture_output=True, text=True)
            return True
        return False


# XXX IMHO those should be verbso n the ReqManager and remove the huge
# indirection between the CLI and the ReqManager. Just instantiating the
# request manager with the parameters like config file centrally makes much
# more sense.


def transaction(
    spooldir=DEFAULT_DIR,
    enc_path=None,
    do_scheduling=True,
    run_all_now=False,
    config_file=None,
    log=_log,
):
    with ReqManager(spooldir, enc_path, config_file, log=log) as rm:
        if do_scheduling:
            rm.schedule()
        rm.execute(run_all_now)
        rm.postpone()
        rm.archive()


def delete(
    reqid, spooldir=DEFAULT_DIR, enc_path=None, config_file=None, log=_log
):
    with ReqManager(spooldir, enc_path, config_file=config_file, log=log) as rm:
        rm.delete(reqid)
        rm.archive()


def listreqs(spooldir=DEFAULT_DIR, config_file=None, log=_log):
    rm = ReqManager(spooldir, config_file=config_file, log=log)
    rm.scan()
    out = str(rm)
    if out:
        print(out)


def main(verbose=False):
    a = argparse.ArgumentParser(
        description="""\
Managed local maintenance requests.
"""
    )
    cmd = a.add_argument_group(
        "actions",
        description="Select activities to be performed (default: "
        "schedule, run, archive)",
    )
    cmd.add_argument(
        "-d",
        "--delete",
        metavar="ID",
        default=None,
        help="delete specified request (see `--list` output)",
    )
    cmd.add_argument(
        "-l",
        "--list",
        action="store_true",
        default=False,
        help="list active maintenance requests",
    )
    cmd.add_argument(
        "-S",
        "--no-scheduling",
        default=False,
        action="store_true",
        help="skip maintenance scheduling, for example to test "
        "local modifications in the request YAML",
    )
    cmd.add_argument(
        "--run-all-now",
        default=False,
        action="store_true",
        help="Just run every maintenance request now, even if it is not due",
    )

    a.add_argument(
        "-c",
        "--config-file",
        metavar="PATH",
        default="/etc/fc-agent.conf",
        help="full path to agent configuration file",
    )
    a.add_argument(
        "-E",
        "--enc-path",
        metavar="PATH",
        default=None,
        help="full path to enc.json",
    )
    a.add_argument(
        "-s",
        "--spooldir",
        metavar="DIR",
        default=DEFAULT_DIR,
        help="requests spool dir (default: %(default)s)",
    )
    a.add_argument("-v", "--verbose", action="store_true", default=verbose)
    args = a.parse_args()

    main_log_file = open("/var/log/fc-maintenance.log", "a")
    cmd_log_file = open(
        "/var/log/fc-agent/fc-maintenance-command-output.log", "w"
    )
    init_logging(args.verbose, main_log_file, cmd_log_file)

    # XXX Switch proper sub-command structure:
    # * schedule
    # * run (--all)
    # * delete
    # * list
    # (why did we need archive as a separate action before?!?)

    # XXX do proper exception logging here in the main() script,
    # convert the module-level functions into reqmanager methods
    # *IF* fc-manage needs to access code through the API, let it instanciate
    # the _fully configured_ request manager directly preferably let
    # exceptions bubble out so we see failure in the agent systemd job
    # properly

    if args.delete and args.list:
        a.error("multually exclusive actions: list + delete")
    if args.delete:
        delete(args.delete, args.spooldir, args.enc_path, args.config_file)
    elif args.list:
        listreqs(args.spooldir, args.config_file)
    else:
        _log.info("fc-maintenance-start")
        transaction(
            args.spooldir,
            args.enc_path,
            not args.no_scheduling,
            args.run_all_now,
            args.config_file,
        )
        _log.info("fc-maintenance-finished")


def list_maintenance():
    """List active maintenance requests on this node."""
    a = argparse.ArgumentParser(
        description=list_maintenance.__doc__,
        epilog="""\
States are: pending (-), due (*), running (=), success (s), tempfail (t),
retrylimit exceeded (r), hard error (e), deleted (d), postponed (p).
""",
    )
    a.add_argument(
        "-d",
        "--spooldir",
        metavar="DIR",
        default=DEFAULT_DIR,
        help="spool dir for requests (default: %(default)s)",
    )
    a.add_argument(
        "-c",
        "--config-file",
        metavar="PATH",
        default="/etc/fc-agent.conf",
        help="full path to agent configuration file",
    )
    args = a.parse_args()
    listreqs(args.spooldir, args.config_file)


if __name__ == "__main__":
    main()
