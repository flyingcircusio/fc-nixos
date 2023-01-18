#!/usr/bin/env python3
import argparse
import json
import logging
import socket
import subprocess
import sys
import traceback

_log = logging.getLogger(__name__)


class Volume(object):
    hostname = socket.gethostname()

    def __init__(self, name):
        self.name = name

    def lock(self):
        tag, locker = self._query_locker()
        _log.info('logstatus tag=%s locker=%s vol=%s', tag, locker, self.name)
        if tag == self.hostname:
            return '"{}" is already locked by "{}", skipping'.format(
                self.name, tag)
        self._rbd('lock', 'add', self.name, self.hostname)

    def unlock(self, force=False):
        tag, locker = self._query_locker()
        _log.info('logstatus tag=%s locker=%s vol=%s', tag, locker, self.name)
        if not tag:
            return '"{}" is not locked, skipping'.format(self.name)
        if tag != self.hostname and not force:
            return 'refusing to unlock "{}", which is locked by "{}"'.format(
                self.name, tag)
        self._rbd('lock', 'remove', self.name, tag, locker)

    def query(self):
        tag, locker = self._query_locker()
        return 'host={} locker_id={}'.format(tag, locker)

    def _rbd(self, *args):
        _log.debug('running cmd: rbd %r', args)
        return subprocess.check_output(
            ['rbd', '--id', self.hostname] + list(args))

    def _query_locker(self):
        lockers = self._rbd('lock', '--format', 'json', 'list', self.name)
        lockers = json.loads(lockers.decode())
        if len(lockers) > 1:
            raise RuntimeError('cannot handle multiple (shared) locks',
                               lockers)
        try:
            locker = lockers[0]
        except IndexError:
            return None, None
        return locker['id'], locker['locker']


def main():
    argp = argparse.ArgumentParser(description=__doc__)
    argp.add_argument('-l', '--lock', help='request a lock on VOLUME',
                      action='store_true', default=False)
    argp.add_argument('-u', '--unlock', help='release a lock on VOLUME',
                      action='store_true', default=False)
    argp.add_argument('-i', '--info', help='determine if VOLUME is locked',
                      action='store_true', default=False)
    argp.add_argument('-f', '--force', help='unlock even if we are not the '
                      'locker', action='store_true', default=False)
    argp.add_argument('-v', '--verbose', help='increase output level',
                      action='count', default=0)
    argp.add_argument('-q', '--quiet', help='suppress regular output',
                      action='store_true', default=False)
    argp.add_argument('volume', metavar='VOLUME',
                      help='volume name (usually POOL/IMAGE)')
    args = argp.parse_args()
    if args.quiet and args.verbose:
        argp.error("-q and -v don't go together")
    if not (args.lock ^ args.unlock ^ args.info):
        argp.error(
            'must specify exactly one of "--lock", "--unlock", "--info"')
    logging.basicConfig(
        stream=sys.stdout, format='{}: %(message)s'.format(argp.prog),
        level={0: logging.WARNING, 1: logging.INFO,
               2: logging.DEBUG}[args.verbose])
    vol = Volume(args.volume)
    try:
        if args.lock:
            out = vol.lock()
        elif args.unlock:
            out = vol.unlock(args.force)
        elif args.info:
            out = vol.query()
        if out and not args.quiet:
            print(out)
    except subprocess.CalledProcessError as e:
        _log.debug('%s', traceback.format_exc())
        sys.exit(1)


if __name__ == '__main__':
    main()
