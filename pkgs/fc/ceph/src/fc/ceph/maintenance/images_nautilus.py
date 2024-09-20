#!/usr/bin/env python3

import base64
import contextlib
import fnmatch
import hashlib
import logging
import os
import os.path as p
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import time
import traceback
import xmlrpc.client
from typing import Iterable, Optional

import requests
from fc.ceph.util import directory, run

CEPH_CONF = "/etc/ceph/ceph.conf"
CEPH_CLIENT = socket.gethostname()
CEPH_POOL = "rbd.hdd"
LOCK_COOKIE = "{}.{}".format(CEPH_CLIENT, os.getpid())

logger = logging.getLogger(__name__)


def environment_data_from_directory(
    enc_path: str = "/etc/nixos/enc.json",
) -> Iterable[dict]:
    with directory.directory_connection(enc_path) as conn:
        return conn.list_environments()


def get_release_images(envdata: Iterable[dict]) -> tuple[Iterable[dict], bool]:
    """filters the gathered environment data according to a release name glob
    and collects all relevant attributes for image loading.

    Return value is a tuple of the data, and as a second element a boolean that
    indicates skipped entries due to parser errors."""
    images = []
    got_errors = False
    for env in envdata:
        # not all releases have metadata, but this is not an error
        try:
            if not env["release_metadata"]:
                continue

            image_data = {
                "environment": env["name"],
                "release_name": env["release_metadata"]["release_name"],
            }

            if not (image_url := env["release_metadata"]["image_url"]):
                logger.info(
                    f"Release {image_data['environment']}/{image_data['release_name']} "
                    "has no image URL, skipping."
                )
                continue
            image_data["image_url"] = image_url

            if not (image_hash := env["release_metadata"]["image_hash"]):
                logger.info(
                    f"Release {image_data['environment']}/{image_data['release_name']} "
                    "has no image hash, skipping."
                )
                continue
            image_data["image_hash"] = image_hash

            images.append(image_data)
        except (KeyError, NameError, TypeError):
            # note down errors for later
            got_errors = True

            logger.exception(f"Received unexpected data from directory:")
            logger.info("Continuing with next item despite error...")

    return (images, got_errors)


class LockingError(Exception):
    pass


def delta_update(from_, to):
    """Update changed blocks between image files.

    We assume that one generation of a VM image does not differ
    fundamentally from the generation before. We only update
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
    logger.debug(
        "\t\t%d/%d 4MiB blocks updated (%d%%)",
        written,
        total,
        100 * written / (max(total, 1)),
    )


def sha256sum_to_sri(sha256sum: str) -> str:
    return (
        f'sha256-{base64.b64encode(sha256sum.encode("ascii")).decode("utf-8")}'
    )


def sri_to_sha256sum(srihash: str) -> str:
    parts = srihash.split("sha256-")
    if len(parts) != 2 or len(parts[0]) or (not len(parts[1])):
        raise ValueError(f"{srihash} is no sha256 SRI hash.")

    return base64.b64decode(parts[1]).decode("utf-8")


class BaseImage:
    def __init__(self, imagedata: dict):
        self.envname = imagedata["environment"]
        self.release_name = imagedata["release_name"]
        self.image_url = imagedata["image_url"]
        self.image_hash_sha256 = sri_to_sha256sum(imagedata["image_hash"])
        self.volume = f"{CEPH_POOL}/{self.envname}"
        self.locker = None

    def __enter__(self):
        """Context manager to maintain Ceph connection.

        Creates image if necessary and locks the image.
        """
        if self.envname not in run.json.rbd("ls", CEPH_POOL):
            logger.info(f"Creating image for {self.envname}")
            run.rbd("create", "-s", str(10 * 2**30) + "B", self.volume)

        # ensure that the context manager unlocks the image in __exit__ before being
        # terminated
        signal.signal(signal.SIGTERM, self._handle_interrupt)
        logger.debug(f"Locking image {self.volume}")
        try:
            run.rbd("lock", "add", self.volume, LOCK_COOKIE)
            self._determine_image_locker()
        except Exception:
            logger.error(f"Could not lock image {self.volume}", exc_info=True)
            raise LockingError()

        return self

    def _determine_image_locker(self):
        locks = run.json.rbd("lock", "ls", self.volume)
        # since Nautilus, `rbd lock ls` returns a list of locker objects
        for lock in locks:
            if lock["id"] == LOCK_COOKIE:
                self.locker = lock["locker"]
                break
        else:
            # all entries tried -> semantically equivalent to a key lookup error
            raise KeyError()

    def __exit__(self, *args, **kw):
        logger.debug(f"Unlocking image {self.volume}")
        try:
            run.rbd(
                # fmt: off
                "lock", "remove",
                f"{CEPH_POOL}/{self.envname}", LOCK_COOKIE, self.locker,
                # fmt: on
            )
        except Exception:
            logger.exception()

    def _handle_interrupt(self, _signum, _stack_frame):
        """Workaround for ensuring image unlocking when the process is terminated
        regularly during the execution of the context's body, inspired by
        https://stackoverflow.com/questions/62642768/how-to-make-a-python-context-manager-catch-a-sigint-or-sigterm-signal
        By raising a SystemExit exception, the context manager's __exit__ is invoked.

        There might still be a potential unlocking gap in the __exit__ function itself,
        see the postponed PEP-419 for details. But that gap is much shorter and thus
        less relevant.
        """
        logger.debug("handling SIGTERM interrupt")
        # explicitly calling own __exit__ is necessary if interrupted during
        # own __enter__ function
        if not self.locker:
            # possibly interrupted in __enter__ before getting own locker information.
            # This is safe because we also still have the LOCK_COOKIE as an
            # identifier to identify whether some other process or host has the lock.
            self._determine_image_locker()
        self.__exit__()
        # SystemExit signals all other potential parent contextes to invoke __exit__
        sys.exit()

    @property
    def _snapshot_names(self):
        return [x["name"] for x in run.json.rbd("snap", "ls", self.volume)]

    @contextlib.contextmanager
    def mapped(self):
        # Has no --format json support
        dev = run.rbd("map", self.volume).decode().strip()
        assert stat.S_ISBLK(os.stat(dev).st_mode)
        try:
            yield dev
        finally:
            run.rbd("unmap", dev)

    def store_in_ceph(self, img):
        """Updates image data from uncompressed image file."""
        logger.info(f"\tStoring in volume {self.volume}")
        img_size = os.stat(img).st_size
        volume_size = run.json.rbd("info", self.volume)["size"]
        if img_size != volume_size:
            run.rbd("resize", "-s", str(img_size) + "B", self.volume)
        with self.mapped() as blockdev:
            delta_update(img, blockdev)

    def update(self):
        """Downloads newest image from Hydra and stores it."""
        current_snapshots = self._snapshot_names
        logger.info(
            "\tHave builds: \n\t\t{}".format("\n\t\t".join(current_snapshots))
        )

        if self.name in current_snapshots:
            # All good. No need to update.
            return

        logger.info("\tDownloading build: {}".format(self.name))
        td, filename = self.download_image()
        uncompressed = filename[0 : filename.rfind(".lz4")]
        subprocess.check_call(["unlz4", "-q", filename, uncompressed])
        os.unlink(filename)
        self.store_in_ceph(uncompressed)
        logger.info("\tCreating snapshot %s", self.name)
        run.rbd("snap", "create", self.snap_spec)
        run.rbd("snap", "protect", self.snap_spec)

    @property
    def name(self):
        return f"{self.release_name}-{self.image_hash_sha256}"

    @property
    def snap_spec(self):
        return self.volume + "@" + self.name

    def download_image(self):
        """Fetches compressed image from Hydra.

        Returns tmpdir handle and filename.
        """
        logging.debug("\t\tGetting %s", self.image_url)
        r = requests.get(self.image_url, stream=True)
        r.raise_for_status()
        chksum = hashlib.sha256()
        size = 0
        td = tempfile.TemporaryDirectory(prefix="image.")
        outfile = p.join(td.name, f"{self.release_name}-{self.envname}")
        logging.debug("\t\tSaving to %s", outfile)
        with open(outfile, "wb") as out:
            for chunk in r.iter_content(4 * 2**20):
                out.write(chunk)
                chksum.update(chunk)
                size += len(chunk)
        if self.image_hash_sha256 != chksum.hexdigest():
            raise RuntimeError(
                f"Image checksum mismatch: expect={self.image_hash_sha256}, got={chksum.hexdigest()}"
            )
        return td, outfile

    def cleanup(self) -> None:
        """Cleanup of old, unneeded snaphshots.

        As a precondition, VMs created from old base snapshots need to be
        flattened (decoupled from that base). Then unprotecting and removing
        is possible.

        This can fail due to a race condition: flatten+unprotect is not an
        atomic operation. Snapshots can still be in use after flattening due to
        a new VM is cloned from the old snapshot in the meantime, hence
        unprotecting fails.
        We accept that race condition, just continue, and try again at the next
        command run.
        """
        snaps: list = run.json.rbd("snap", "ls", self.volume)
        snap_specs = [self.volume + "@" + snap["name"] for snap in snaps]

        # hard invariant: always keep at least 1 snapshot per image
        if len(snap_specs) == 1:
            return
        # Do not clean up the current one.
        # Also: expect that we successfully downloaded it) if that didn't
        # happen we SHOULD have already errored out much much earlier,
        # so this is a hard assert. Also notices if the only imag left is not
        # the current one.
        assert self.snap_spec in snap_specs
        snap_specs.remove(self.snap_spec)

        # Now delete the remaining snapshots.
        for snap_spec in snap_specs:
            # Decouple VMs created from their base snapshots.
            for child in run.json.rbd("children", snap_spec):
                logger.info(
                    "\tFlattening {}/{}".format(child["pool"], child["image"])
                )
                try:
                    run.rbd("flatten", child["pool"] + "/" + child["image"])
                except Exception:
                    logger.exception(
                        "Error trying to flatten {}/{}".format(
                            child["pool"], child["image"]
                        )
                    )

            # unprotecting a non-flattened image throws an error.
            logger.info("\tPurging snapshot " + snap_spec)
            try:
                run.rbd("snap", "unprotect", snap_spec)
            except Exception:
                logger.exception(
                    "Error trying to unprotect snapshot, it might still be in use:"
                )
            try:
                run.rbd("snap", "rm", snap_spec)
            except Exception:
                logger.exception("Error trying to remove snapshot:")


def load_vm_images() -> int:
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
    status_code: int = 0

    environments = environment_data_from_directory()
    image_data, processing_errors = get_release_images(environments)
    for releasedata in image_data:
        envname = releasedata["environment"]
        logger.info(f"Updating environment {envname}")
        try:
            with BaseImage(releasedata) as image:
                image.update()
                image.cleanup()
        except LockingError:
            logger.exception(f"Could not lock image for {envname}.")
            status_code = max(69, status_code)
            logger.info("Continuing with next branch despite error...")
        # In general, we decide to continue with the next branch when an exception happens.
        # If there are certain exceptions where the whole process needs to be aborted,
        # that exception needs to be cought specifically.
        except Exception:
            logger.exception(f"An error occured while updating `{envname}`.")
            status_code = max(1, status_code)
            logger.info("Continuing with next image despite error...")

    if processing_errors:
        status_code = max(1, status_code)
    return status_code
