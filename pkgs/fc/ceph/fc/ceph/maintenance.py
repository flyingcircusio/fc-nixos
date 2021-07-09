"""Configure pools on Ceph storage servers according to the directory."""

import argparse
import logging
import os
import pprint
import sys

import fc.ceph.images
import fc.util.directory
from fc.ceph.api import Cluster, Pools


class ResourcegroupPoolEquivalence(object):
    """Ensure that required Ceph pools exist."""

    REQUIRED_POOLS = ['rbd', 'data', 'metadata', 'rbd.hdd']

    def __init__(self, directory, cluster):
        self.directory = directory
        self.pools = Pools(cluster)

    def actual(self):
        return set(p for p in self.pools.names())

    def ensure(self):
        exp = set(self.REQUIRED_POOLS)
        act = self.actual()
        for pool in exp - act:
            print('creating pool {}'.format(pool))
            self.pools.create(pool)


class VolumeDeletions(object):

    def __init__(self, directory, cluster):
        self.directory = directory
        self.pools = Pools(cluster)

    def ensure(self):
        deletions = self.directory.deletions('vm')
        for name, node in list(deletions.items()):
            print(name, node)
            if 'hard' not in node['stages']:
                continue
            for pool in self.pools:
                try:
                    images = list(pool.images)
                except KeyError:
                    # The pool doesn't exist. Ignore. Nothing to delete anyway.
                    continue

                for image in ['{}.root', '{}.swap', '{}.tmp']:
                    image = image.format(name)
                    base_image = None
                    for rbd_image in images:
                        if rbd_image.image != image:
                            continue
                        if not rbd_image.snapshot:
                            base_image = rbd_image
                            continue
                        # This is a snapshot of the volume itself.
                        print("Purging snapshot {}/{}@{}".format(
                            pool.name, image, rbd_image.snapshot))
                        pool.snap_rm(rbd_image)
                    if base_image is None:
                        continue
                    print("Purging volume {}/{}".format(pool.name, image))
                    pool.image_rm(base_image)


class MaintenanceTasks(object):

    def load_vm_images(self):
        fc.ceph.images.load_vm_images()

    def purge_old_snapshots(self):
        pools = Pools(Cluster())
        for pool in pools:
            for image in pool.images:
                if image.is_outdated_snapshot:
                    print('removing snapshot {}/{}'.format(
                        pool.name, image.name))
                    pool.snap_rm(image)

    def clean_deleted_vms(self):
        ceph = Cluster()
        enc = fc.util.directory.load_default_enc_json()
        directory = fc.util.directory.connect()
        volumes = VolumeDeletions(directory, ceph)
        volumes.ensure()
        rpe = ResourcegroupPoolEquivalence(directory, ceph)
        rpe.ensure()
