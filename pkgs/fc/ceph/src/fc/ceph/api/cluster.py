"""Access to a specific Ceph cluster."""

import configparser
import socket
import subprocess

CEPH_ID = socket.gethostname()
CEPH_CONF = "/etc/ceph/ceph.conf"


class CephCmdError(RuntimeError):
    pass


class Cluster(object):
    """Exposes configuration and provides access to admin commands."""

    def __init__(
        self,
        ceph_conf=CEPH_CONF,
        ceph_id=CEPH_ID,
        default_encoding="utf-8",
    ):
        self.ceph_conf = ceph_conf
        self.config = None  # lazy ConfigParser init
        self.ceph_id = ceph_id
        self.default_encoding = default_encoding

    def parse_config(self):
        self.config = configparser.ConfigParser()
        with open(self.ceph_conf) as f:
            self.config.read_file(f)

    def default_pool_size(self):
        """Returns (size, min_size) pair."""
        if not self.config:
            self.parse_config()
        return (
            self.config.getint("global", "osd_pool_default_size"),
            self.config.getint("global", "osd_pool_default_min_size"),
        )

    def default_pg_num(self):
        """Returns default pg count for new pools."""
        if not self.config:
            self.parse_config()
        try:
            return self.config.getint("global", "osd_pool_default_pg_num")
        except configparser.NoOptionError:
            # ceph default value
            return 8

    def generic_ceph_cmd(self, base_args, more_args, accept_failure=False):
        """Generic command wrapper for Ceph command line tools.

        Executes a command line constructed from a static prefix
        (base_args) and individual parameters (more_args). If
        accept_failure is True, a triple (stdout, stderr, returncode)
        is returned. If we do not accept failures anyway, only a tuple
        is return if the command invocation succeeds.
        """
        p = subprocess.Popen(
            base_args + list(more_args),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        stdout, stderr = p.communicate()
        if accept_failure:
            return (stdout, stderr, p.returncode)
        if p.returncode != 0:
            raise CephCmdError(
                "{} failed".format(base_args[0]),
                more_args,
                stdout,
                stderr,
                p.returncode,
            )
        return (stdout, stderr)

    def rbd(self, args, accept_failure=False):
        """RBD command line wrapper."""
        return self.generic_ceph_cmd(
            ["rbd", "--id", self.ceph_id, "-c", self.ceph_conf],
            args,
            accept_failure,
        )

    def ceph_osd(self, args, accept_failure=False):
        """Ceph OSD command line wrapper."""
        return self.generic_ceph_cmd(
            [
                "ceph",
                "--id",
                self.ceph_id,
                "-c",
                self.ceph_conf,
                "--format=json",
                "osd",
            ],
            args,
            accept_failure,
        )
