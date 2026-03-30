"""Access to a specific Ceph cluster."""

import configparser

CEPH_CONF = "/etc/ceph/ceph.conf"


class Cluster(object):
    """Exposes configuration and provides access to admin commands."""

    def __init__(self, ceph_conf=CEPH_CONF):
        # XXX customising the ceph_conf is not used or exposed somewhere, consider removing
        self.ceph_conf = ceph_conf
        self.config = None  # lazy ConfigParser init

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
