"""Manage maintenance requests."""

from fc.maintenance.activity import RebootType
from .request import Request
from .state import State, ARCHIVE
from fc.util.logging import init_logging
import argparse
import fc.util.directory
import fcntl
import glob
import json
import os
import os.path as p
import socket
import structlog
import subprocess

DEFAULT_DIR = '/var/spool/maintenance'

_log = structlog.get_logger()


def require_lock(func):
    """Decorator that asserts an open lockfile prior execution."""

    def assert_locked(self, *args, **kwargs):
        assert self.lockfile, 'method {} required lock'.format(func)
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

    TIMEFMT = '%Y-%m-%d %H:%M:%S %Z'

    directory = None
    lockfile = None
    in_maintenance = False  # 'maintenance' flag set in directory

    def __init__(self, spooldir=DEFAULT_DIR, enc_path=None, log=_log):
        """Initialize ReqManager and create directories if necessary."""
        self.spooldir = spooldir
        self.requestsdir = p.join(self.spooldir, 'requests')
        self.archivedir = p.join(self.spooldir, 'archive')
        for d in (self.spooldir, self.requestsdir, self.archivedir):
            if not p.exists(d):
                os.mkdir(d)
        self.enc_path = enc_path
        self.log = log
        self.requests = {}

    def __enter__(self):
        if self.lockfile:
            return self
        self.lockfile = open(p.join(self.spooldir, '.lock'), 'a+')
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

    def __str__(self):
        """Human-readable listing of active maintenance requests."""
        if not self.requests:
            return ''
        return ('St Id       Scheduled             Estimate  Comment\n' +
                '\n'.join((str(r) for r in sorted(self.requests.values()))))

    def dir(self, request):
        """Return file system path for request identified by `reqid`."""
        return p.realpath(p.join(self.requestsdir, request.id))

    def scan(self):
        self.requests = {}
        for d in glob.glob(p.join(self.requestsdir, '*')):
            if not p.isdir(d):
                continue
            try:
                req = Request.load(d, self.log)
                req._reqmanager = self
                self.requests[req.id] = req
            except Exception as exc:
                with open(p.join(d, '_load_request_yaml_error'), 'a') as f:
                    print(exc, file=f)
                self.log.error(
                    "request-load-error",
                    _replace_msg=
                    "Loading {request} failed, archiving request. See exception for details.",
                    request=p.basename(d),
                    exc_info=True)
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
                    _replace_msg=
                    "When adding {request}, found identical request {duplicate}. Nothing added.",
                    request=request.id,
                    duplicate=duplicate.id)
                return None
        self.requests[request.id] = request
        request.dir = self.dir(request)
        request._reqmanager = self
        request.save()
        self.log.info(
            "request-added",
            _replace_msg="Added request: {request}",
            request=request.id,
            comment=request.comment)
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
        self.log.debug('schedule-start')
        schedule_maintenance = {
            reqid: {
                'estimate': int(req.estimate),
                'comment': req.comment
            }
            for reqid, req in self.requests.items()
        }
        if schedule_maintenance:
            self.log.debug(
                "schedule-maintenances",
                request_count=len(schedule_maintenance))

        result = self.directory.schedule_maintenance(schedule_maintenance)
        disappeared = set()
        for key, val in result.items():
            try:
                req = self.requests[key]
                self.log.debug("schedule-request", request=key, data=val)
                if req.update_due(val['time']):
                    self.log.info(
                        "schedule-change-start-time",
                        _replace_msg="Changing start time of {request} to {at}",
                        request=req.id,
                        at=val["time"])
                    req.save()
            except KeyError:
                self.log.warning(
                    "schedule-request-disappeared",
                    _replace_msg=
                    "Request {request} disappeared, marking as deleted.",
                    request=key)
                disappeared.add(key)
        if disappeared:
            self.directory.end_maintenance(
                {key: {
                    'result': 'deleted'
                }
                 for key in disappeared})

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
        """Set myself in 'maintenance' mode.

        This method is idempotent since we need to call it for every
        request. ReqManager's current design does not allow to query if
        there are runnable requests at all without causing side effects
        (humm). Tolerates directory failures as there a some maintenance
        actions that need to proceed anyway.
        """
        if self.in_maintenance:
            self.log.debug("enter-maintenance-skip")
            return
        try:
            self.log.debug("enter-maintenance")
            self.directory.mark_node_service_status(socket.gethostname(),
                                                    False)
            self.in_maintenance = True
        except socket.error:
            self.log.error(
                "enter-maintenance-error",
                _replace_msg=
                "Failed to set 'out of service' directory flag. See exception for details.",
                exc_info=True)

    def leave_maintenance(self):
        try:
            self.log.debug('leave-maintenance')
            self.directory.mark_node_service_status(socket.gethostname(), True)
            self.in_maintenance = False
        except socket.error:
            self.log.error(
                "leave-maintenance-error",
                _replace_msg=
                "Failed to set 'in service' directory flag. See exception for details.",
                exc_info=True)

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
                _replace_msg=
                "Run all mode requested, treating all requests as runnable.")
            runnable_requests = list(self.requests.values())
        else:
            runnable_requests = list(self.runnable())
        if runnable_requests:
            runnable_count = len(runnable_requests)
            if runnable_count == 1:
                msg = "Executing one runnable maintenance request."
            else:
                msg = "Executing {runnable_count} runnable maintenance requests."
            self.log.info(
                "execute-requests-runnable",
                _replace_msg=msg,
                runnable_count=runnable_count)
        else:
            self.log.info(
                "execute-requests-empty",
                _replace_msg="No runnable maintenance requests.")

        requested_reboots = set()
        try:
            for req in runnable_requests:
                self.log.info(
                    "execute-request-start",
                    _replace_msg="Starting execution of request: {request}",
                    request=req.id)
                self.enter_maintenance()
                try:
                    req.execute()
                except Exception:
                    self.log.error(
                        "execute-request-failed",
                        _replace_msg=
                        "Executing request {request} failed. See exception for details.",
                        request=req.id,
                        exc_info=True)
                    req.state = State.error
                    execution_finished = False
                else:
                    execution_finished = True
                try:
                    req.save()
                except Exception:
                    # This was ignored before.
                    # At least log what's happening here even if it's not critical.
                    self.log.debug(
                        "execute-save-request-failed", exc_info=True)

                if execution_finished:
                    attempt = req.attempts[-1]
                    if req.state == State.error:
                        self.log.info(
                            "execute-request-finished-error",
                            _replace_msg="Error executing request {request}.",
                            request=req.id,
                            stdout=attempt.stdout,
                            stderr=attempt.stderr,
                            duration=attempt.duration,
                            returncode=attempt.returncode)
                    else:
                        if req.activity.reboot_needed is not None:
                            requested_reboots.add(req.activity.reboot_needed)
                        self.log.info(
                            "execute-request-finished",
                            _replace_msg=
                            "Executed request {request} (state: {state}).",
                            request=req.id,
                            state=req.state,
                            duration=attempt.duration)

            if requested_reboots:
                # Rebooting while still in maintenance.
                self.reboot(requested_reboots)
            else:
                self.leave_maintenance()
                self.log.debug("no-reboot-requested")

        except Exception:
            self.leave_maintenance()
            self.log.debug("execute-requests-failed", exc_info=True)

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
            req.id: {
                'postpone_by': 2 * int(req.estimate)
            }
            for req in postponed
        }
        self.log.debug(
            'postpone-maintenance-directory', args=postpone_maintenance)
        self.directory.postpone_maintenance(postpone_maintenance)
        for req in postponed:
            req.update_due(None)
            req.save()

    @require_lock
    @require_directory
    def archive(self):
        """Move all completed requests to archivedir."""
        self.log.debug('archive-start')
        archived = [r for r in self.requests.values() if r.state in ARCHIVE]
        if not archived:
            return
        end_maintenance = {
            req.id: {
                'duration': req.duration,
                'result': str(req.state)
            }
            for req in archived
        }
        self.log.debug(
            "archive-end-maintenance-directory", args=end_maintenance)
        self.directory.end_maintenance(end_maintenance)
        for req in archived:
            self.log.info(
                "archive-request",
                _replace_msg="Request {request} completed, archiving request.",
                request=req.id)
            dest = p.join(self.archivedir, req.id)
            os.rename(req.dir, dest)
            req.dir = dest
            req.save()

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
                request=reqid)
            return
        req.state = State.deleted
        req.save()
        self.log.info(
            "delete-finished",
            _replace_msg="Marked request {request} as deleted",
            request=req.id)

    def reboot(self, requested_reboots):
        if RebootType.COLD in requested_reboots:
            self.log.info(
                "maintenance-poweroff",
                _replace=
                "Doing a cold boot now to finish maintenance activities.")
            subprocess.run(
                "poweroff", check=True, capture_output=True, text=True)
        elif RebootType.WARM in requested_reboots:
            self.log.info(
                "maintenance-reboot",
                _replace_msg="Rebooting now to finish maintenance activities.")
            subprocess.run(
                "reboot", check=True, capture_output=True, text=True)


def transaction(spooldir=DEFAULT_DIR,
                enc_path=None,
                do_scheduling=True,
                run_all_now=False,
                log=_log):
    with ReqManager(spooldir, enc_path, log=log) as rm:
        if do_scheduling:
            rm.schedule()
        rm.execute(run_all_now)
        rm.postpone()
        rm.archive()


def delete(reqid, spooldir=DEFAULT_DIR, enc_path=None, log=_log):
    with ReqManager(spooldir, enc_path, log=log) as rm:
        rm.delete(reqid)
        rm.archive()


def listreqs(spooldir=DEFAULT_DIR, log=_log):
    rm = ReqManager(spooldir, log=log)
    rm.scan()
    out = str(rm)
    if out:
        print(out)


def main(verbose=False):
    a = argparse.ArgumentParser(description="""\
Managed local maintenance requests.
""")
    cmd = a.add_argument_group(
        'actions',
        description='Select activities to be performed (default: '
        'schedule, run, archive)')
    cmd.add_argument(
        '-d',
        '--delete',
        metavar='ID',
        default=None,
        help='delete specified request (see `--list` output)')
    cmd.add_argument(
        '-l',
        '--list',
        action='store_true',
        default=False,
        help='list active maintenance requests')
    cmd.add_argument(
        '-S',
        '--no-scheduling',
        default=False,
        action='store_true',
        help='skip maintenance scheduling, for example to test '
        'local modifications in the request YAML')
    cmd.add_argument(
        '--run-all-now',
        default=False,
        action='store_true',
        help='Just run every maintenance request now, even if it is not due')

    a.add_argument(
        '-E',
        '--enc-path',
        metavar='PATH',
        default=None,
        help='full path to enc.json')
    a.add_argument(
        '-s',
        '--spooldir',
        metavar='DIR',
        default=DEFAULT_DIR,
        help='requests spool dir (default: %(default)s)')
    a.add_argument('-v', '--verbose', action='store_true', default=verbose)
    args = a.parse_args()

    main_log_file = open('/var/log/fc-maintenance.log', 'a')
    cmd_log_file = open('/var/log/fc-agent/fc-maintenance-command-output.log',
                        'w')
    init_logging(args.verbose, main_log_file, cmd_log_file)

    if args.delete and args.list:
        a.error('multually exclusive actions: list + delete')
    if args.delete:
        delete(args.delete, args.spooldir, args.enc_path)
    elif args.list:
        listreqs(args.spooldir)
    else:
        _log.info("fc-maintenance-start")
        transaction(args.spooldir, args.enc_path, not args.no_scheduling,
                    args.run_all_now)
        _log.info("fc-maintenance-finished")


def list_maintenance():
    """List active maintenance requests on this node."""
    a = argparse.ArgumentParser(
        description=list_maintenance.__doc__,
        epilog="""\
States are: pending (-), due (*), running (=), success (s), tempfail (t),
retrylimit exceeded (r), hard error (e), deleted (d), postponed (p).
""")
    a.add_argument(
        '-d',
        '--spooldir',
        metavar='DIR',
        default=DEFAULT_DIR,
        help='spool dir for requests (default: %(default)s)')
    args = a.parse_args()
    listreqs(args.spooldir)


if __name__ == '__main__':
    main()
