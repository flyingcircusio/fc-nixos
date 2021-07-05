"""Check Ceph overall cluster health.

This check parses `ceph status` output and generates various metrics. It is
intended to be run on all Ceph mons.
"""

import argparse
import json
import logging
import re
import subprocess

import nagiosplugin

DEFAULT_LOGFILE = '/var/log/ceph/ceph.log'
_log = logging.getLogger('nagiosplugin')


class CephStatus(object):
    """Encapsulates ceph status output and provides easy access."""

    def __init__(self, status_cmd):
        self.cmd = status_cmd
        self._raw = None
        self.status = None

    def query(self):
        _log.info('querying cluster status with "%s"', self.cmd)
        self._raw = subprocess.check_output(self.cmd, shell=True).decode()
        _log.debug('cluster status output:\n%s', self._raw)
        self.status = json.loads(self._raw)

    @property
    def overall(self):
        return self.status['health']['overall_status']

    @property
    def summary(self):
        """Return one-line cluster health summary.

        Sometimes, the "summary" fields are empty and there is just some
        stuff in the "detail" fields. In this case, we return a random
        detail.
        """
        res = ', '.join(elem['summary']
                        for elem in self.status['health']['summary'])
        if res:
            return res
        elif self.detail:
            return self.detail[0]
        return ''

    @property
    def detail(self):
        """Detailed status (e.g., clock skew) as list."""
        return self.status['health']['detail']

    @property
    def data_bytes(self):
        """Net amount of saved data (excluding replicas)."""
        return int(self.status['pgmap']['data_bytes'])

    @property
    def bytes_total(self):
        """Gross storage space in cluster (including replicas)."""
        return int(self.status['pgmap']['bytes_total'])

    @property
    def bytes_used(self):
        """Gross amount of saved data including replicas."""
        return int(self.status['pgmap']['bytes_used'])

    @property
    def bytes_avail(self):
        return int(self.status['pgmap']['bytes_avail'])

    @property
    def bytes_net_total(self):
        return self.bytes_used + self.bytes_avail

    @property
    def read_rate(self):
        try:
            return int(self.status['pgmap']['read_bytes_sec'])
        except KeyError:
            return 0

    @property
    def write_rate(self):
        try:
            return int(self.status['pgmap']['write_bytes_sec'])
        except KeyError:
            return 0

    @property
    def ops(self):
        try:
            return int(self.status['pgmap']['op_per_sec'])
        except KeyError:
            return 0

    @property
    def recovery_rate(self):
        try:
            return int(self.status['pgmap']['recovering_bytes_per_sec'])
        except KeyError:
            return 0

    @property
    def degraded_ratio(self):
        try:
            return float(self.status['pgmap']['degraded_ratio']) * 100.0
        except KeyError:
            return 0.0

    @property
    def misplaced_ratio(self):
        try:
            return float(self.status['pgmap']['misplaced_ratio']) * 100.0
        except KeyError:
            return 0.0


class Ceph(nagiosplugin.Resource):
    """Status data aquisition and parsing."""

    def __init__(self, status):
        self.stat = status
        self.summary = ''
        self.usage_ratio = 0.0

    def probe(self):
        self.stat.query()
        self.summary = self.stat.summary
        _log.debug('summary=%s', self.summary.strip())
        for detail in self.stat.detail:
            _log.info('detail=%s', detail.strip())
        yield nagiosplugin.Metric('health', self.stat.overall)
        yield nagiosplugin.Metric('net data', self.stat.data_bytes, 'B', min=0,
                                  context='default')
        m = re.search(r'(\d+) near full osd', self.summary)
        nearfull = int(m.group(1)) if m else 0
        yield nagiosplugin.Metric(
            'nearfull', nearfull, min=0, context='nearfull')
        if self.stat.bytes_net_total:
            self.usage_ratio = self.stat.bytes_used / self.stat.bytes_net_total
            yield nagiosplugin.Metric(
                'usage', float('{:5.4}'.format(100.0 * self.usage_ratio)), '%',
                min=0.0, max=100.0, context='default')
        yield nagiosplugin.Metric('client read', self.stat.read_rate, 'B/s',
                                  min=0, context='default')
        yield nagiosplugin.Metric('client write', self.stat.write_rate, 'B/s',
                                  min=0, context='default')
        yield nagiosplugin.Metric('client ops', self.stat.ops, 'op/s', min=0,
                                  context='default')
        yield nagiosplugin.Metric('recovery rate', self.stat.recovery_rate,
                                  'B/s', min=0, context='default')
        yield nagiosplugin.Metric('degraded pgs', self.stat.degraded_ratio,
                                  '%', min=0.0, max=100.0, context='default')
        yield nagiosplugin.Metric('misplaced pgs', self.stat.misplaced_ratio,
                                  '%', min=0.0, max=100.0, context='default')


class CephLog(nagiosplugin.Resource):
    """Scan log file for blocked requests."""

    def __init__(self, logfile, statefile):
        self.logfile = logfile
        self.cookie = nagiosplugin.Cookie(statefile)

    r_slow_req = re.compile(
        r' (\d+) slow requests.*; oldest blocked for > ([0-9.]+) secs')

    def probe(self):
        blocked = 0
        oldest = 0.0
        _log.info('scanning %s for slow request logs', self.logfile)
        with nagiosplugin.LogTail(self.logfile, self.cookie) as newlines:
            for line in newlines:
                m = self.r_slow_req.search(line.decode())
                if not m:
                    continue
                _log.debug('slow requests: %s', line.strip())
                blocked = max(blocked, int(m.group(1)))
                oldest = max(oldest, float(m.group(2)))
        return [
            nagiosplugin.Metric('req_blocked', blocked, min=0),
            nagiosplugin.Metric('req_blocked_age', oldest, 's', min=0),
        ]


class HealthContext(nagiosplugin.Context):

    def evaluate(self, metric, resource):
        health = metric.value
        hint = resource.summary
        if ('HEALTH_CRIT' in health or 'HEALTH_ERR' in health):
            return self.result_cls(nagiosplugin.Critical, hint, metric)
        if 'HEALTH_WARN' in health:
            return self.result_cls(nagiosplugin.Warn, hint, metric)
        if 'HEALTH_OK' in health:
            return self.result_cls(nagiosplugin.Ok, hint, metric)
        raise RuntimeError('cannot parse health status', health)


class UsageSummary(nagiosplugin.Summary):

    def ok(self, results):
        """Include overall usage information into green status output."""
        return '{:5.2f}% capacity used'.format(
            results['usage'].resource.usage_ratio * 100.0)


@nagiosplugin.guarded
def main():
    argp = argparse.ArgumentParser()
    argp.add_argument('-w', '--warn-usage', metavar='RANGE', default='0.8',
                      help='warn if cluster usage ratio is outside RANGE')
    argp.add_argument('-c', '--crit-usage', metavar='RANGE', default='0.9',
                      help='crit if cluster usage ratio is outside RANGE')
    argp.add_argument('-k', '--command', default='ceph status --format=json',
                      help='execute command to retrieve cluster status '
                      '(default: "%(default)s")')
    argp.add_argument('-l', '--log', metavar='PATH', default=DEFAULT_LOGFILE,
                      help='scan log file for slow requests (default: '
                      '%(default)s)')
    argp.add_argument('-r', '--warn-requests', metavar='RANGE', default=1,
                      help='warn if number of blocked requests exceeds range '
                      '(default: %(default)s)')
    argp.add_argument('-R', '--crit-requests', metavar='RANGE', default=50,
                      help='crit if number of blocked requests exceeds range '
                      '(default: %(default)s)')
    argp.add_argument('-a', '--warn-blocked-age', metavar='RANGE', default=30,
                      help='warn if age of oldest blocked request is outside '
                      'range (default: %(default)s)')
    argp.add_argument('-A', '--crit-blocked-age', metavar='RANGE', default=90,
                      help='crit if age of oldest blocked request is outside '
                      'range (default: %(default)s)')
    argp.add_argument('-s', '--state', metavar='PATH',
                      default='/var/lib/check_ceph_health.state',
                      help='state file for logteil (default: %(default)s)')
    argp.add_argument('-v', '--verbose', action='count', default=0,
                      help='increase output level')
    argp.add_argument('-t', '--timeout', default=30, metavar='SEC',
                      help='abort execution after SEC seconds')
    args = argp.parse_args()
    check = nagiosplugin.Check(
        Ceph(CephStatus(args.command)),
        HealthContext('health'),
        nagiosplugin.ScalarContext('nearfull', critical='0:0',
                                   fmt_metric='{value} near full osd(s)'),
        UsageSummary())
    if args.log:
        check.add(
            CephLog(args.log, args.state),
            nagiosplugin.ScalarContext('req_blocked', args.warn_requests,
                                       args.crit_requests),
            nagiosplugin.ScalarContext(
                'req_blocked_age', args.warn_blocked_age,
                args.crit_blocked_age),
        )
    check.main(args.verbose, args.timeout)
