"""Generates /etc/backy.conf from directory data."""

import argparse
import copy
import json
import logging
import logging.handlers
import os
import os.path as p
import shutil
import socket
import subprocess
import syslog

import fc.util.configfile
import fc.util.directory
import yaml

_log = logging.getLogger(__name__)
BASEDIR = '/srv/backy'


class BackyConfig(object):
    """Represents a complete backy configuration."""

    prefix = ''
    hostname = socket.gethostname()

    def __init__(self, location, consul_acl_token):
        self.location = location
        self.consul_acl_token = consul_acl_token
        self.changed = False
        self._deletions = None

    def apply(self, restart=False):
        """Updates configuration file and reloads daemon if necessary."""
        self.generate_config()
        self.purge()
        if self.changed and restart:
            _log.info('config changed, restarting backy')
            subprocess.check_call(['systemctl', 'reload', 'backy'])

    @property
    def deletions(self):
        """Cached copy of nodes marked in directory for deletion."""
        if not self._deletions:
            d = fc.util.directory.connect()
            self._deletions = d.deletions('vm')
        return self._deletions

    def job_config(self):
        """Returns data structure for "jobs" config file section.

        Goes over all nodes in the current location and selects those
        that are assigned to the current backup server and are not
        marked for deletion.

        Schedules may have variants which are separated by a hyphen,
        e.g. "default-full".
        """
        d = fc.util.directory.connect(ring='max')
        vms = d.list_virtual_machines(self.location)
        jobs = {}
        for vm in vms:
            name = vm['name']
            if vm['parameters'].get('backy_server') != self.hostname:
                continue
            if 'soft' in self.deletions.get(name, {'stages': []})['stages']:
                continue
            schedule = vm['parameters'].get('backy_schedule', 'default')
            variant = None
            if '-' in schedule:
                schedule, variant = schedule.split('-', 1)
            jobs[name] = {
                'source': {
                    'type': 'flyingcircus',
                    'consul_acl_token': self.consul_acl_token,
                    'image': vm['name'] + '.root',
                    'pool': vm['parameters']['rbd_pool'],
                    'vm': name,
                    'full-always': (variant == 'full'),
                },
                'schedule': schedule,
            }
        return jobs

    def generate_config(self):
        """Writes main backy configuration file.

        Returns True if file has been changed.
        """
        global_conf = self.prefix + '/etc/backy.global.conf'
        with open(global_conf) as f:
            config = yaml.safe_load(f)
        config['jobs'] = self.job_config()
        output = fc.util.configfile.ConfigFile(self.prefix + '/etc/backy.conf',
                                               mode=0o640)
        output.write("# Managed by fc-backy, do not edit\n\n")
        yaml.safe_dump(config, output)
        self.changed = output.commit()

    def purge(self):
        """Removes job directories for nodes that are marked for deletion."""
        for name, node in self.deletions.items():
            if 'purge' not in node['stages']:
                continue
            node_dir = self.prefix + p.join(BASEDIR, name)
            if p.exists(node_dir):
                _log.info('purging backups for deleted node %s', name)
                shutil.rmtree(node_dir, ignore_errors=True)


def main():
    a = argparse.ArgumentParser(description=__doc__)
    a.add_argument('-r',
                   '--restart',
                   default=False,
                   action='store_true',
                   help='restart backy on config changes')
    args = a.parse_args()

    h = logging.handlers.SysLogHandler(facility=syslog.LOG_LOCAL4)
    logging.basicConfig(level=logging.DEBUG, handlers=[h])
    with open('/etc/consul.json') as f:
        consul_config = json.load(f)
    with open('/etc/nixos/enc.json') as f:
        enc = json.load(f)
    b = BackyConfig(enc['parameters']['location'],
                    consul_config['acl']['tokens']['agent'])

    b.apply(restart=args.restart)
