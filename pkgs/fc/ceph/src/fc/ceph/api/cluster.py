"""Access to a specific Ceph cluster."""

import configparser
from typing import Any

from fc.ceph.util import run

CEPH_CONF = "/etc/ceph/ceph.conf"


class Cluster(object):
    """Exposes configuration and provides access to admin commands."""

    def __init__(self, ceph_conf=CEPH_CONF):
        # XXX customising the ceph_conf is not used or exposed somewhere, consider removing
        self.ceph_conf = ceph_conf
        self.config = None  # lazy ConfigParser init

    # Thin convenience wrappers around the `run.*` runners that apply this
    # cluster's config file.

    def ceph(self, *args: str, **kwargs) -> Any:
        return run.ceph("-c", self.ceph_conf, *args, **kwargs)

    def ceph_json(self, *args: str, **kwargs) -> Any:
        return run.json.ceph("-c", self.ceph_conf, *args, **kwargs)

    def rbd(self, *args: str, **kwargs) -> Any:
        return run.rbd("-c", self.ceph_conf, *args, **kwargs)

    def rbd_json(self, *args: str, **kwargs) -> Any:
        return run.json.rbd("-c", self.ceph_conf, *args, **kwargs)

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
