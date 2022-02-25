#!/usr/bin/env python3

import contextlib
import hashlib
import logging
import os
import os.path as p
import socket
import stat
import subprocess
import sys
import tempfile
import time

import rados
import rbd
import requests

RELEASES = [
    "fc-19.03-dev",
    "fc-19.03-staging",
    "fc-19.03-production",
    "fc-20.09-dev",
    "fc-20.09-staging",
    "fc-20.09-production",
    "fc-21.05-dev",
    "fc-21.05-staging",
    "fc-21.05-production",
    "fc-21.11-dev",
    "fc-21.11-staging",
]
CEPH_CONF = "/etc/ceph/ceph.conf"
CEPH_CLIENT = socket.gethostname()
CEPH_POOL = "rbd.hdd"
LOCK_COOKIE = "{}.{}".format(CEPH_CLIENT, os.getpid())

logger = logging.getLogger(__name__)


class LockingError(Exception):
    pass


def build_url(build_id, download=False):
    url = "https://hydra.flyingcircus.io/build/{}".format(build_id)
    if download:
        url += "/download/1"
    return url


def hydra_build_info(build_id):
    """Queries build metadata.

    Expected API response::
    {
      "job": "images.fc",
      "drvpath":
        "/nix/store/sqrb…-nixos-fc-18.09.44.ba01a3b-x86_64-linux.drv",
      "buildoutputs": {
        "out": {
          "path": "/nix/store/9i3x…-nixos-fc-18.09.44.ba01a3b-x86_64-linux"
        }
      },
      "jobset": "fc-18.09-dev",
      "project": "flyingcircus",
      "jobsetevals": [2470],
      "buildstatus": 0,
      "system": "x86_64-linux",
      "finished": 1,
      "nixname": "nixos-fc-18.09.44.ba01a3b-x86_64-linux",
      "id": 50957,
      "buildproducts": {
        "1": {
          "sha256hash": "2e1b017aa3…",
          "filesize": 428987844,
          "type": "file",
          "name": "nixos-fc-18.09.44.ba01a3b-x86_64-linux.img.lz4",
          "subtype": "img",
          "sha1hash": "39a59622…"
        }
      }
    }

    Returns buildproduct dict.
    """
    r = requests.get(
        build_url(build_id), headers={"Accept": "application/json"}
    )
    r.raise_for_status()
    meta = r.json()
    buildproduct = meta["buildproducts"]["1"]
    if not buildproduct["type"] == "file":
        raise RuntimeError("Cannot find build product in server response", meta)
    return buildproduct


def download_image(build_id):
    """Fetches compressed image from Hydra.

    Returns tmpdir handle and filename.
    """
    buildproduct = hydra_build_info(build_id)
    url = build_url(build_id, download=True)
    logging.debug("\t\tGetting %s", url)
    r = requests.get(url, stream=True)
    r.raise_for_status()
    chksum = hashlib.sha256()
    size = 0
    td = tempfile.TemporaryDirectory(prefix="image.")
    outfile = p.join(td.name, buildproduct["name"])
    logging.debug("\t\tSaving to %s", outfile)
    with open(outfile, "wb") as out:
        for chunk in r.iter_content(4 * 2**20):
            out.write(chunk)
            chksum.update(chunk)
            size += len(chunk)
    expected_size = buildproduct["filesize"]
    if expected_size != size:
        raise RuntimeError(
            "Image size mismatch: expect={}, got={}", expected_size, size
        )
    expected_hash = buildproduct["sha256hash"]
    if expected_hash != chksum.hexdigest():
        raise RuntimeError(
            "Image checksum mismatch: expect={}, got={}",
            expected_hash,
            chksum.hexdigest(),
        )
    return td, outfile


def delta_update(from_, to):
    """Update changed blocks between image files.

    We assume that one generation of a VM image does not differ
    fundamentatlly from the generation before. We only update
    changed blocks. Additionally, we use a stuttering technique to
    improve fairness.
    """
    logger.debug("\t\tUpdating...")
    blocksize = 4 * 2**20
    total = 0
    written = 0
    with open(from_, "rb") as source:
        with open(to, "r+b") as dest:
            while True:
                a = source.read(blocksize)
                if not a:
                    break
                total += 1
                b = dest.read(blocksize)
                if a != b:
                    dest.seek(-len(b), os.SEEK_CUR)
                    dest.write(a)
                    written += 1
                    time.sleep(0.01)
    logger.debug(
        "\t\t%d/%d 4MiB blocks updated (%d%%)",
        written,
        total,
        100 * written / (max(total, 1)),
    )


class BaseImage:

    cluster = None
    ioctx = None
    rbd = None
    image = None

    def __init__(self, release):
        self.release = release

    def __enter__(self):
        """Context manager to maintain Ceph connection.

        Creates image if necessary and locks the image.
        """
        self.cluster = rados.Rados(
            conffile=CEPH_CONF, name="client.{}".format(CEPH_CLIENT)
        )
        self.cluster.connect()
        self.ioctx = self.cluster.open_ioctx(CEPH_POOL)
        self.rbd = rbd.RBD()

        if self.release not in self.rbd.list(self.ioctx):
            logger.info("Creating image for {}".format(self.release))
            self.rbd.create(self.ioctx, self.release, 10 * 2**30)
        self.image = rbd.Image(self.ioctx, self.release)

        # Ensure we have a lock - stop handling for this image
        # and clean up (exceptions in __enter__ do not automatically
        # cause __exit__ being called).
        logger.debug("Locking image %s", self.release)
        try:
            self.image.lock_exclusive(LOCK_COOKIE)
        except rbd.ImageBusy:
            self.force_unlock_if_dead_client()
            try:
                self.image.lock_exclusive(LOCK_COOKIE)
            except Exception:
                logger.error("Could not lock image %s", self.release)
                raise LockingError()
        except rbd.ImageExists:
            # _We_ locked the image. Proceed.
            pass

        return self

    def __exit__(self, *args, **kw):
        try:
            self.image.unlock(LOCK_COOKIE)
        except Exception:
            logger.exception()
        self.image.close()
        self.ioctx.close()
        self.cluster.shutdown()

    def force_unlock_if_dead_client(self):
        lck = self.image.list_lockers()
        if not lck:
            return
        logger.debug("Examining lock on image %s (%r)", self.release, lck)
        client, cookie, _addr = lck["lockers"][0]  # excl -> max one lock
        try:
            otherhost, otherpid = cookie.split(".", 1)
            otherpid = int(otherpid)
        except (IndexError, ValueError):
            logger.error("Failed to parse lock cookie %s", cookie)
            raise LockingError()
        if otherhost != CEPH_CLIENT:
            return
        try:
            os.kill(otherpid, 0)
            logger.warn("Lock held by process %d -- still alive", otherpid)
        except OSError:
            # no such process
            logger.debug("Breaking lock %s.%s", client, cookie)
            self.image.break_lock(client, cookie)

    @property
    def _snapshot_names(self):
        return [x["name"] for x in self.image.list_snaps()]

    @property
    def volume(self):
        return "{}/{}".format(CEPH_POOL, self.release)

    @contextlib.contextmanager
    def mapped(self):
        dev = subprocess.check_output(
            ["rbd", "--id", CEPH_CLIENT, "map", self.volume]
        )
        dev = dev.decode().strip()
        assert stat.S_ISBLK(os.stat(dev).st_mode)
        try:
            yield dev
        finally:
            subprocess.check_call(["rbd", "--id", CEPH_CLIENT, "unmap", dev])

    def store_in_ceph(self, img):
        """Updates image data from uncompressed image file."""
        logger.info("\tStoring in volume %s/%s", CEPH_POOL, self.release)
        self.image.resize(os.stat(img).st_size)
        with self.mapped() as blockdev:
            delta_update(img, blockdev)

    def newest_hydra_build(self):
        """Checks Hydra for the newest release.

        Expected API response::
        [
          {
            "project": "flyingcircus",
            "id": 50957,
            "jobset": "fc-18.09-dev",
            "finished": 1,
            "system": "x86_64-linux",
            "nixname": "nixos-fc-18.09.44.ba01a3b-x86_64-linux",
            "job": "images.fc",
            "buildstatus": 0,
            "timestamp": 1552383072
          },
          ...
        ]
        Note that this list may contain failed builds.
        """
        r = requests.get(
            "https://hydra.flyingcircus.io/api/latestbuilds",
            headers={"Accept": "application/json"},
            params={
                "nr": 5,
                "project": "flyingcircus",
                "jobset": self.release,
                "job": "images.fc",
            },
        )
        r.raise_for_status()
        builds = r.json()
        for b in builds:
            if b["buildstatus"] != 0:
                continue
            build_id = int(b["id"])
            assert build_id > 0
            return build_id
        raise RuntimeError("Failed to query API for newest build")

    def update(self):
        """Downloads newest image from Hydra and stores it."""
        build_id = self.newest_hydra_build()
        name = "build-{}".format(build_id)
        current_snapshots = self._snapshot_names
        if name in current_snapshots:
            # All good. No need to update.
            return

        logger.info(
            "\tHave builds: \n\t\t{}".format("\n\t\t".join(current_snapshots))
        )
        logger.info("\tDownloading build: {}".format(name))
        td, filename = download_image(build_id)
        uncompressed = filename[0 : filename.rfind(".lz4")]
        subprocess.check_call(["unlz4", "-q", filename, uncompressed])
        os.unlink(filename)
        self.store_in_ceph(uncompressed)
        logger.info("\tCreating snapshot %s", name)
        self.image.create_snap(name)
        self.image.protect_snap(name)

    def flatten(self):
        """Decouple VMs created from their base snapshots."""
        logger.debug("Flattening child images for %s", self.release)
        for snap in self.image.list_snaps():
            snap = rbd.Image(self.ioctx, self.release, snap["name"])
            for child_pool, child_image in snap.list_children():
                logger.info(
                    "\tFlattening {}/{}".format(child_pool, child_image)
                )
                try:
                    pool = self.cluster.open_ioctx(child_pool)
                    image = rbd.Image(pool, child_image)
                    image.flatten()
                except Exception:
                    logger.exception(
                        "Error trying to flatten {}/{}".format(
                            child_pool, child_image
                        )
                    )
                finally:
                    image.close()
                    pool.close()
                time.sleep(5)  # give Ceph room catch up with I/O

    def purge(self):
        """Delete old images, but keep the last three.

        Keeping a few is good because there may be race conditions that
        images are currently in use even after we called flatten. (This
        is what unprotect does, but there is no way to run flatten/unprotect
        in an atomic fashion. However, we expect all clients to always use
        the newest one. So, the race condition that remains is that we just
        downloaded a new image and someone else created a VM while we added
        it and didn't see the new snapshot, but we already were done
        flattening. Keeping 3 should be more than sufficient.

        If the ones we want to purge won't work, then we just ignore that
        for now.

        The CLI returns snapshots in their ID order (which appears to be
        guaranteed to increase) but the API isn't documented. Lets order
        them ourselves to ensure reliability.
        """
        snaps = list(self.image.list_snaps())
        snaps.sort(key=lambda x: x["id"])
        for snap in snaps[:-3]:
            logger.info(
                "\tPurging snapshot {}/{}@{}".format(
                    CEPH_POOL, self.release, snap["name"]
                )
            )
            try:
                self.image.unprotect_snap(snap["name"])
                self.image.remove_snap(snap["name"])
            except Exception:
                logger.exception("Error trying to purge snapshot:")


def load_vm_images():
    level = logging.INFO
    try:
        if int(os.environ.get("VERBOSE", 0)):
            level = logging.DEBUG
    except Exception:
        pass
    logging.basicConfig(level=level, format="%(message)s")
    requests_log = logging.getLogger("urllib3")
    requests_log.setLevel(logging.WARNING)
    requests_log.propagate = True
    try:
        for branch in RELEASES:
            logger.info("Updating branch {}".format(branch))
            with BaseImage(branch) as image:
                image.update()
                image.flatten()
                image.purge()
    except LockingError:
        sys.exit(69)
    except Exception:
        logger.exception(
            "An error occured while updating branch `{}`".format(branch)
        )
        sys.exit(1)
