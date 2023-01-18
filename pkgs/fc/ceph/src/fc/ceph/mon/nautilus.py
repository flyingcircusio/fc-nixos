import configparser
import errno
import glob
import os
import re
import resource
import shutil
import socket
import sys
import tempfile
import threading
import time
import traceback
from subprocess import CalledProcessError

from fc.ceph.util import find_lv_path, find_vg_for_mon, kill, mount_status, run


class Monitor(object):
    def __init__(self):
        self.id = socket.gethostname()
        self.mon_dir = f"/srv/ceph/mon/ceph-{self.id}"
        self.pid_file = f"/run/ceph/mon.{self.id}.pid"

    def activate(self):
        print(f"Activating MON {self.id}...")
        resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))

        if not mount_status(self.mon_dir):
            run.mount(
                # fmt: off
                "-t", "xfs", "-o", "defaults,nodev,nosuid",
                "LABEL=ceph-mon", self.mon_dir,
                # fmt: on
            )
        run.ceph_mon("-i", self.id, "--pid-file", self.pid_file)

    def deactivate(self):
        print(f"Stopping MON {self.id} ...")
        kill(self.pid_file)

    def reactivate(self):
        try:
            self.deactivate()
        except Exception:
            pass
        self.activate()

    def create(self, size="8g", lvm_vg=None, bootstrap_cluster=False):
        print(f"Creating MON {self.id}...")

        if os.path.exists(self.mon_dir):
            print(
                "There already exists a mon dir. "
                "Please destroy existing mon data first."
            )
            sys.exit(1)

        if not os.path.exists(self.mon_dir):
            os.makedirs(self.mon_dir)

        if not lvm_vg:
            try:
                lvm_vg = find_vg_for_mon()
            except IndexError:
                print(
                    "Could not find a journal VG. Please prepare a journal "
                    "VG first using `fc-ceph osd prepare-journal`."
                )
                sys.exit(1)

        lvm_lv = "ceph-mon"
        lvm_data_device = f"/dev/{lvm_vg}/{lvm_lv}"

        print(f"creating new mon volume {lvm_data_device}")
        run.lvcreate("-n", lvm_lv, f"-L{size}", lvm_vg)
        run.mkfs_xfs("-L", lvm_lv, "-m", "crc=1,finobt=1", lvm_data_device)
        run.mount(
            # fmt: off
            "-t", "xfs",
            "-o", "defaults,nodev,nosuid",
            "LABEL=ceph-mon", self.mon_dir,
            # fmt: on
        )

        tmpdir = tempfile.mkdtemp()

        config = configparser.ConfigParser()
        with open("/etc/ceph/ceph.conf") as f:
            config.read_file(f)
        if bootstrap_cluster:
            # Generate initial mon keyring
            run.ceph_authtool(
                # fmt: off
                "-g",
                "-n", "mon.",
                "--create-keyring", f"{tmpdir}/keyring",
                "--cap", "mon", "allow *",
                # fmt: on
            )
            # Import admin keyring
            run.ceph_authtool(
                # fmt: off
                f"{tmpdir}/keyring",
                "--import-keyring", "/etc/ceph/ceph.client.admin.keyring",
                # fmt: on
            )
            # adjust admin capabilities
            run.ceph_authtool(
                # fmt: off
                f"{tmpdir}/keyring",
                "--cap", "mds", "allow *",
                "--cap", "mon", "allow *",
                "--cap", "osd", "allow *",
                "--cap", "mgr", "allow *",
                # fmt: on
            )
            # Generate initial monmap
            fsid = config["global"]["fsid"]
            run.monmaptool("--create", "--fsid", fsid, f"{tmpdir}/monmap")
        else:
            # Retrieve mon key and monmap
            run.ceph(
                # fmt: off
                "-n", "client.admin",
                "auth", "get", "mon.",
                "-o", f"{tmpdir}/keyring",
                # fmt: on
            )
            run.ceph("mon", "getmap", "-o", f"{tmpdir}/monmap")

        # Add yourself to the monmap
        run.monmaptool(
            "--add",
            self.id,
            config[f"mon.{self.id}"]["public addr"],
            f"{tmpdir}/monmap",
        )
        # Create mon on disk structures
        run.ceph_mon(
            # fmt: off
            "-i", self.id,
            "--mkfs",
            "--keyring", f"{tmpdir}/keyring",
            "--monmap", f"{tmpdir}/monmap",
            # fmt: on
        )

        shutil.rmtree(tmpdir)

        run.systemctl("start", "fc-ceph-mon")

    def destroy(self):
        try:
            lvm_data_device = find_lv_path("ceph-mon")
        except ValueError:
            lvm_data_device = None

        run.systemctl("stop", "fc-ceph-mon")
        try:
            self.deactivate()
        except Exception:
            pass

        run.ceph("mon", "remove", self.id)
        run.umount(self.mon_dir)

        if lvm_data_device:
            run.wipefs("-q", "-a", lvm_data_device, check=False)
            run.lvremove("-f", lvm_data_device, check=False)

        os.rmdir(self.mon_dir)
