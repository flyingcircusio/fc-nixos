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

    def num_hosts_per_root(self, root: str = "default") -> int:
        """Count available hosts of a crush root.
        Deliberately does **not** filter any further for actually **availability**
        of OSDs, because these filters are affected by our regular host maintenances.
        The OSDs existing is enough."""

        crush_nodes: dict["str", Any] = {
            entry["id"]: entry
            for entry in self.ceph_json("osd", "tree")["nodes"]
        }
        working_set_ids = [
            n["id"]
            for n in crush_nodes.values()
            if n["type"] == "root" and n["name"] == root
        ]
        if not working_set_ids:
            raise ValueError(f"Could not find crush root {root}.")
        hosts: set[str] = set()
        while working_set_ids:
            node = crush_nodes[working_set_ids.pop()]
            if node["type"] != "host":
                working_set_ids.extend(node.get("children", []))
            # only add hosts with an OSD
            elif any(
                crush_nodes[child_id]["type"] == "osd"
                for child_id in node["children"]
                if child_id in crush_nodes
            ):
                hosts.add(node["id"])

        return len(hosts)
