"""Localconfig VM management.

Most of this code has been migrated to Consul-triggered fc.qemu stuff.
"""

import glob
import logging
import logging.handlers
import os
import os.path
import subprocess
import sys
import syslog
from multiprocessing.pool import ThreadPool
from pathlib import Path

import fc.util.directory
import fc.util.enc

_log = logging.getLogger(__name__)


class VM(object):
    """Minimal VM abstraction to support config cleanup testing.

    Calls to fc-qemu are set up in such a way that stdout/stderr goes
    into /var/log/fc-qemu.log
    """

    root = ""  # support testing
    configfile = "{root}/etc/qemu/vm/{name}.cfg"

    def __init__(self, name):
        self.name = name
        self.cfg = self.configfile.format(root=VM.root, name=name)

    def unlink(self):
        """Idempotent config delete action"""
        if os.path.exists(self.cfg):
            _log.debug("cleaning {}".format(self.cfg))
            os.unlink(self.cfg)

    def ensure(self):
        """Check single VM"""
        cmd = ["fc-qemu", "ensure", self.name]
        _log.debug("calling: " + " ".join(cmd))
        return subprocess.call(cmd, close_fds=True)


def delete_configs():
    """Prune VM configs for deleted VMs."""
    directory = fc.util.directory.connect()
    deletions = directory.deletions("vm")
    for name, node in deletions.items():
        if "hard" in node["stages"]:
            VM(name).unlink()


def update_all_rg_users():
    directory = fc.util.directory.connect(ring="max")
    _log.info("retrieve-all-rg-users")
    Path("/etc/qemu/users").mkdir(exist_ok=True)
    try:
        rgs = directory.list_resource_groups()
    except Exception:
        _log.warning("retrieve-all-resource-groups-failed", exc_info=True)
        return
    for rg in rgs:
        try:
            users = directory.list_users(rg)
        except Exception:
            _log.warning("retrieve-all-rg-users-failed", exc_info=True)
            continue
        try:
            fc.util.enc.conditional_update(
                f"/etc/qemu/users/{rg}.json", users, 0o640
            )
        except (IOError, OSError):
            fc.util.enc.inplace_update(f"/etc/qemu/users/{rg}.json", users)


def main():
    h = logging.handlers.SysLogHandler(facility=syslog.LOG_LOCAL4)
    logging.basicConfig(level=logging.DEBUG, handlers=[h])

    update_all_rg_users()
    results = []
    pool = ThreadPool(5)
    for cfg in glob.glob("/etc/qemu/vm/*.cfg"):
        vm = VM(os.path.basename(cfg).rsplit(".", 1)[0])
        results.append(pool.apply_async(vm.ensure))
    pool.close()
    pool.join()
    exitcodes = [x.get() for x in results] or (0,)

    # Normally VMs should have been shut down already when we delete the config
    # but doing this last also gives a chance this still happening right
    # before.
    delete_configs()
    sys.exit(max(exitcodes))
