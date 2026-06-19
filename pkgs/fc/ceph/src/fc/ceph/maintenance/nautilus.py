"""Configure pools on Ceph storage servers according to the directory."""

import re
import socket
import subprocess
import sys
import time
import traceback
from subprocess import CalledProcessError

import fc.util.directory
from fc.ceph.api import Cluster, Pools
from fc.ceph.maintenance import noup_workaround
from fc.ceph.maintenance.images_nautilus import (
    load_vm_images as load_vm_images_task,
)
from fc.ceph.util import run


class ResourcegroupPoolEquivalence(object):
    """Ensure that required Ceph pools exist."""

    REQUIRED_POOLS = ["rbd", "rbd.hdd"]

    def __init__(self, directory, cluster):
        self.directory = directory
        self.pools = Pools(cluster)

    def actual(self):
        return set(p for p in self.pools.names())

    def ensure(self) -> int:
        status_code = 0
        exp = set(self.REQUIRED_POOLS)
        act = self.actual()
        for pool in exp - act:
            print("creating pool {}".format(pool))
            try:
                self.pools.create(pool)
            except CalledProcessError:
                print(
                    "The following error occured at pool creation:",
                    file=sys.stderr,
                )
                traceback.print_exc()
                print("Continuing...", file=sys.stderr)
                status_code = 12

        return status_code

    def ensure_pools_are_balanceable(self):
        """For all pools that have a default value of `pg_num_min`, set that
        property to `1`.
        We have many pools that are almost empty by design, like `rbd`. The
        pg_autoscaler assigns at least `pg_num_min` PGs to each pool, which
        defaults to `32` and is a waste of PGs in smaller clusters. Let's allow
        going down to 1 PG if needed. Unfortunately there is no configurable
        default value.
        This behaviour *might* improve in Ceph Quincy.
        """
        for pool in self.pools:
            if not pool.pg_num_min:
                pool.pg_num_min = 1


class VolumeDeletions(object):
    def __init__(self, directory, cluster):
        self.directory = directory
        self.pools = Pools(cluster)

    def ensure(self) -> int:
        status_code = 0
        deletions = self.directory.deletions("vm")
        for name, node in list(deletions.items()):
            print(name, node)
            if "hard" not in node["stages"]:
                continue
            for pool in self.pools:
                try:
                    images = list(pool.images)
                except KeyError:
                    # The pool doesn't exist. Ignore. Nothing to delete anyway.
                    continue

                for image in ["{}.root", "{}.swap", "{}.tmp"]:
                    image = image.format(name)
                    base_image = None
                    for rbd_image in images:
                        if rbd_image.image != image:
                            continue
                        if not rbd_image.snapshot:
                            base_image = rbd_image
                            continue
                        # This is a snapshot of the volume itself.
                        print(
                            "Purging snapshot {}/{}@{}".format(
                                pool.name, image, rbd_image.snapshot
                            )
                        )
                        try:
                            pool.snap_rm(rbd_image)
                        except CalledProcessError:
                            print(
                                "The following error occured at snapshot deletion:",
                                file=sys.stderr,
                            )
                            traceback.print_exc()
                            status_code = max(status_code, 10)
                            print("Continuing...", file=sys.stderr)

                    if base_image is None:
                        continue
                    print("Purging volume {}/{}".format(pool.name, image))
                    try:
                        pool.image_rm(base_image)
                    except CalledProcessError:
                        print(
                            "The following error occured at volume deletion:",
                            file=sys.stderr,
                        )
                        traceback.print_exc()
                        status_code = max(status_code, 11)
                        print("Continuing...", file=sys.stderr)

        return status_code


def get_host_crush_buckets() -> tuple[set[str], set[str]]:
    """Return  the names of the crush buckets that correspond with the
    host entries of this host as well as their associated OSD IDs.
    """
    hostname = socket.gethostname()
    osd_tree = run.json.ceph("osd", "tree")

    osds: set[str] = set()

    # Find the host entries in the crush map associated with this host
    host_map_entries = set()
    for node in osd_tree["nodes"]:
        if node["type"] != "host":
            continue
        if node["name"].split("-")[0] != hostname:
            continue
        host_map_entries.add(node["name"])
        osds.update(map(str, node["children"]))

    return host_map_entries, osds


def filter_noup_osds(osd_ids: set[str]) -> set[str]:
    """Filters the input set of OSD IDs to return only the OSDs that currently
    have a NOUP flag."""
    matched_noup_osds = set()
    ceph_health = run.json.ceph("health", "detail")

    match_fmt = re.compile(r"^osd.(?P<osdid>\d+) has flags noup$")
    try:
        for detail in ceph_health["checks"]["OSD_FLAGS"]["detail"]:
            if match_result := match_fmt.match(detail["message"]):
                matched_noup_osds.add(match_result.group("osdid"))
    except KeyError:
        # no such health warning issued
        pass
    return matched_noup_osds & osd_ids


class MaintenanceTasks(object):
    """Controller that holds a number of maintenance-related methods."""

    # the names of warnings that shall not prevent hosts from entering maintenance
    IGNORED_WARNINGS = [
        "PG_NOT_DEEP_SCRUBBED",
        "PG_NOT_SCRUBBED",
        "LARGE_OMAP_OBJECTS",
        "MANY_OBJECTS_PER_PG",
    ]

    LOCKTOOL_TIMEOUT_SECS = 30
    UNLOCK_MAX_RETRIES = 5

    def check_cluster_maintenance(self, status: dict) -> bool:
        """Takes the ceph cluster status information as a dict,
        returns True if the cluster is clean enough for doing maintenance operations.
        """
        overall_status = status["status"]
        if overall_status == "HEALTH_OK":
            # cluster healthy, everything is fine
            return True
        elif overall_status == "HEALTH_WARN":
            # there are warnings, but maybe only ones we can ignore?
            triggered_checks = status["checks"]
            for check_name in self.IGNORED_WARNINGS:
                try:
                    triggered_checks.pop(check_name)
                except KeyError:
                    # this is fine, non-active acceptable warnings can be ignored
                    pass
            return True if len(triggered_checks) == 0 else False
        else:
            return False

    def load_vm_images(self) -> int:
        return load_vm_images_task()

    def purge_old_snapshots(self) -> int:
        status_code = 0
        pools = Pools(Cluster())
        for pool in pools:
            for image in pool.images:
                if image.is_outdated_snapshot:
                    print(
                        "removing snapshot {}/{}".format(pool.name, image.name)
                    )
                    try:
                        pool.snap_rm(image)
                    except CalledProcessError:
                        print(
                            "The following error occured at snapshot deletion:",
                            file=sys.stderr,
                        )
                        traceback.print_exc()
                        status_code = 13
                        print("Continuing...", file=sys.stderr)

        return status_code

    def clean_deleted_vms(self) -> int:
        ceph = Cluster()
        directory = fc.util.directory.connect()
        volumes = VolumeDeletions(directory, ceph)
        volume_statuscode = volumes.ensure()
        rpe = ResourcegroupPoolEquivalence(directory, ceph)
        rpe_statuscode = rpe.ensure()
        # piggybacking this for now
        rpe.ensure_pools_are_balanceable()
        return max(volume_statuscode, rpe_statuscode)

    def _ensure_maintenance_volume(self, lock_name: str):
        try:
            # fmt: off
            run.rbd_locktool("-q", "-i", f"rbd/{lock_name}",
                timeout=self.LOCKTOOL_TIMEOUT_SECS,
            )
            # fmt: on
        except subprocess.CalledProcessError:
            run.rbd("create", "--size", "1", f"rbd/{lock_name}")

    def lock(self, lock_name: str):
        try:
            self._ensure_maintenance_volume(lock_name)
            # Aquire the maintenance lock
            run.rbd_locktool(
                "-l", f"rbd/{lock_name}", timeout=self.LOCKTOOL_TIMEOUT_SECS
            )
        # locking can block on a busy cluster, causing the whole agent (and all other
        # agent operations waiting for the global agent lock) to be stuck
        except subprocess.TimeoutExpired:
            # We cannot know whether the lock has succeeded despite the timeout, so
            # attempt an unlock again.
            self.leave()
            sys.exit(75)  # EXIT_TEMPFAIL, fc-agent might retry
        # already locked by someone else
        except subprocess.CalledProcessError:
            sys.exit(75)  # EXIT_TEMPFAIL, fc-agent might retry

    def enter(self):
        self.lock(".maintenance")

        # Check that the cluster is fully healhty
        cluster_status = run.json.ceph("health")
        if not self.check_cluster_maintenance(cluster_status):
            print(
                f"Can not enter maintenance: "
                f"Ceph status is {cluster_status['status']}."
            )
            # when postponing the maintenance, do not leave a stale lock around in case
            # e.g. the machine failing before the next maintenance attempt.
            # This also sets our own OSDs `up` again, in case they might have
            # been the culprit behind the unhealthy status.
            self.leave()
            # 69 signals to postpone the maintenance, triggering a leave in fc-agent
            sys.exit(69)

        # Prohibit OSD traffic by marking them down and flagging them to
        # not automatically return.
        try:
            _, osd_ids = get_host_crush_buckets()
            if osd_ids:
                run.ceph("osd", "set-group", "noup", *sorted(osd_ids))
                run.ceph("osd", "down", *sorted(osd_ids))
        except Exception:
            # `leave` is necessary once we started setting OSDs noup/ down,
            # as down OSDs will cause the next lock-time health check to fail
            self.leave()
            sys.exit(75)  # EXIT_TEMPFAIL, fc-agent might retry

    def unlock(self, lock_name: str):
        last_exc = None
        for _ in range(self.UNLOCK_MAX_RETRIES):
            try:
                self._ensure_maintenance_volume(lock_name)
                # fmt: off
                run.rbd_locktool("-q", "-u", f"rbd/{lock_name}",
                    timeout=self.LOCKTOOL_TIMEOUT_SECS,
                )
                # fmt: on
            except subprocess.TimeoutExpired as e:
                print(f"WARNING: Maintenance leave timed out at {e.cmd}.")
                last_exc = e
                time.sleep(
                    self.LOCKTOOL_TIMEOUT_SECS / 5
                )  # cooldown time for cluster
                continue
            break
        else:
            print(
                "WARNING: All maintenance leave attempts have timed out, "
                "the cluster might not be properly unlocked."
            )
            # deliberately re-raise the exception, as this situation shall be checked by
            # an operator
            raise (
                last_exc
                if last_exc
                else RuntimeError("Ceph cluster maintenance unlock failed")
            )

    def leave(self):
        _, osd_ids = get_host_crush_buckets()

        noup_osds = sorted(filter_noup_osds(osd_ids))
        for osd_id in noup_osds:
            # remove noup flags in a staggered fashion, to reduce peering storm
            run.ceph("osd", "unset-group", "noup", str(osd_id))
            time.sleep(15)

        if noup_osds and noup_workaround.run() != 0:
            raise RuntimeError("noup-workaround failed, PGs may still be stuck")

        self.unlock(".maintenance")
