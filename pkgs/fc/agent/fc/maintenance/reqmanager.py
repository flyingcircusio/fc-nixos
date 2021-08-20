"""Manage maintenance requests."""

from .request import Request
from .state import State, ARCHIVE
import argparse
import fc.util.directory
import fcntl
import glob
import json
import logging
import os
import os.path as p
import socket

LOG = logging.getLogger(__name__)
DEFAULT_DIR = '/var/spool/maintenance'


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

    def __init__(self, spooldir=DEFAULT_DIR, enc_path=None):
        """Initialize ReqManager and create directories if necessary."""
        self.spooldir = spooldir
        self.requestsdir = p.join(self.spooldir, 'requests')
        self.archivedir = p.join(self.spooldir, 'archive')
        for d in (self.spooldir, self.requestsdir, self.archivedir):
            if not p.exists(d):
                os.mkdir(d)
        self.enc_path = enc_path
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
                req = Request.load(d)
                req._reqmanager = self
                self.requests[req.id] = req
            except Exception as exc:
                LOG.exception('error loading request from %s', d)
                with open(p.join(d, '_load_request_yaml_error'), 'a') as f:
                    print(exc, file=f)
                LOG.error('(req %s) archiving defective request',
                          p.basename(d))
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
                LOG.info('(req %s) found identical request %s, skipping',
                         request.id, duplicate.id)
                return None
        self.requests[request.id] = request
        request.dir = self.dir(request)
        request._reqmanager = self
        request.save()
        LOG.info('(req %s) created: %s', request.id, request.comment)
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
        LOG.debug('scheduling maintenance requests')
        schedule_maintenance = {
            reqid: {
                'estimate': int(req.estimate),
                'comment': req.comment
            }
            for reqid, req in self.requests.items()
        }
        if schedule_maintenance:
            LOG.debug('scheduling requests: %s', schedule_maintenance)
        result = self.directory.schedule_maintenance(schedule_maintenance)
        disappeared = set()
        for key, val in result.items():
            try:
                req = self.requests[key]
                LOG.debug('(req %s) updating request: %s', key, val)
                if req.update_due(val['time']):
                    LOG.info('(req %s) changing start time to %s', req.id,
                             val['time'])
                    req.save()
            except KeyError:
                LOG.warning('(req %s) request disappeared, marking as deleted',
                            key)
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
            return
        try:
            LOG.debug('marking node as "out of service"')
            self.directory.mark_node_service_status(socket.gethostname(),
                                                    False)
            self.in_maintenance = True
        except socket.error:
            LOG.error('failed to set "out of service" directory flag')

    def leave_maintenance(self):
        try:
            LOG.debug('marking node as "in service"')
            self.directory.mark_node_service_status(socket.gethostname(), True)
            self.in_maintenance = False
        except socket.error:
            LOG.error('failed to set "in service" directory flag')

    @require_directory
    @require_lock
    def execute(self):
        """Process maintenance requests.

        If there is an already active request, run to termination first.
        After that, select the oldest due request as next active request.
        """
        LOG.debug('executing maintenance requests')
        try:
            for req in self.runnable():
                LOG.info('(req %s) starting execution', req.id)
                self.enter_maintenance()
                try:
                    req.execute()
                except Exception:
                    LOG.exception('(req %s) error during execution', req.id)
                    req.state = State.error
                try:
                    req.save()
                except Exception:
                    pass
                LOG.debug('(req %s) executed, state %s', req.id, req.state)
        finally:
            self.leave_maintenance()

    @require_lock
    @require_directory
    def postpone(self):
        """Instructs directory to postpone requests.

        Postponed requests get their new scheduled time with the next
        schedule call.
        """
        LOG.debug('postponing maintenance requests')
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
        LOG.debug('invoking postpone_maintenance(%s)', postpone_maintenance)
        self.directory.postpone_maintenance(postpone_maintenance)
        for req in postponed:
            req.update_due(None)
            req.save()

    @require_lock
    @require_directory
    def archive(self):
        """Move all completed requests to archivedir."""
        LOG.debug('archiving maintenance requests')
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
        LOG.debug('invoking end_maintenance(%s)', end_maintenance)
        self.directory.end_maintenance(end_maintenance)
        for req in archived:
            LOG.info('(req %s) completed, archiving request', req.id)
            dest = p.join(self.archivedir, req.id)
            os.rename(req.dir, dest)
            req.dir = dest
            req.save()

    @require_lock
    def delete(self, reqid):
        LOG.debug('trying to delete request matching %s', reqid)
        req = None
        for i in self.requests:
            if i.startswith(reqid):
                req = self.requests[i]
                break
        if not req:
            LOG.warning('cannot locate request matching %s', reqid)
            return
        req.state = State.deleted
        req.save()
        LOG.info('(req %s) marking as deleted', req.id)


def transaction(spooldir=DEFAULT_DIR, enc_path=None, do_scheduling=True):
    with ReqManager(spooldir, enc_path) as rm:
        if do_scheduling:
            rm.schedule()
        rm.execute()
        rm.postpone()
        rm.archive()


def delete(reqid, spooldir=DEFAULT_DIR, enc_path=None):
    with ReqManager(spooldir, enc_path) as rm:
        rm.delete(reqid)
        rm.archive()


def listreqs(spooldir=DEFAULT_DIR):
    rm = ReqManager(spooldir)
    rm.scan()
    out = str(rm)
    if out:
        print(out)


def setup_logging(verbose=False):
    logging.basicConfig(
        format='MAINT:%(levelname)s: %(message)s',
        level=logging.DEBUG if verbose else logging.INFO)
    # this is really annoying
    logging.getLogger('iso8601').setLevel(logging.INFO)


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
    setup_logging(args.verbose)
    if args.delete and args.list:
        a.error('multually exclusive actions: list + delete')
    if args.delete:
        delete(args.delete, args.spooldir, args.enc_path)
    elif args.list:
        listreqs(args.spooldir)
    else:
        transaction(args.spooldir, args.enc_path, not args.no_scheduling)


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
