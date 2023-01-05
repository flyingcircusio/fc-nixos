"""Configure pools on Ceph storage servers according to the directory."""

import json
import subprocess
import sys
import traceback

import fc.util.directory
from fc.ceph.api import Cluster, Pools
from fc.ceph.api.cluster import CephCmdError
from fc.ceph.maintenance.images_nautilus import (
    load_vm_images as load_vm_images_task,
)
from fc.ceph.util import kill, mount_status, run


class ResourcegroupPoolEquivalence(object):
    """Ensure that required Ceph pools exist."""

    REQUIRED_POOLS = ["rbd", "data", "metadata", "rbd.hdd"]

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
            except CephCmdError:
                print(
                    "The following error occured at pool creation:",
                    file=sys.stderr,
                )
                traceback.print_exc()
                print("Continuing...", file=sys.stderr)
                status_code = 12

        return status_code


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
                        except CephCmdError:
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
                    except CephCmdError:
                        print(
                            "The following error occured at volume deletion:",
                            file=sys.stderr,
                        )
                        traceback.print_exc()
                        status_code = max(status_code, 11)
                        print("Continuing...", file=sys.stderr)

        return status_code


class MaintenanceTasks(object):
    """Controller that holds a number of maintenance-related methods."""

    # the names of warnings that shall not prevent hosts from entering maintenance
    IGNORED_WARNINGS = [
        "PG_NOT_DEEP_SCRUBBED",
        "PG_NOT_SCRUBBED",
    ]

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

    def load_vm_images(self):
        load_vm_images_task()

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
                    except CephCmdError:
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
        return max(volume_statuscode, rpe_statuscode)

    def _ensure_maintenance_volume(self):
        try:
            run.rbd_locktool("-q", "-i", "rbd/.maintenance")
        except subprocess.CalledProcessError as e:
            run.rbd("create", "--size", "1", "rbd/.maintenance")

    def enter(self):
        self._ensure_maintenance_volume()
        # Aquire the maintenance lock
        run.rbd_locktool("-l", "rbd/.maintenance")
        # Check that the cluster is fully healhty
        cluster_status = run.json.ceph("health")
        if not self.check_cluster_maintenance(cluster_status):
            print(
                f"Can not enter maintenance: "
                f"Ceph status is {cluster_status['status']}."
            )
            # 69 signals to postpone the maintenance, triggering a leave in fc-agent
            sys.exit(69)

    def leave(self):
        self._ensure_maintenance_volume()
        run.rbd_locktool("-q", "-u", "rbd/.maintenance")
