import configparser
import resource
import shutil
import socket
import tempfile

from fc.ceph.lvm import XFSCephVolume
from fc.ceph.util import kill, run


def find_vg_for_mon():
    vgsys = False
    for vg in run.json.vgs():
        if vg["vg_name"].startswith("vgjnl"):
            return vg["vg_name"]
        if vg["vg_name"] == "vgsys":
            vgsys = True

    if vgsys:
        print(
            "WARNING: using volume group `vgsys` because no journal "
            "volume group was found."
        )
        return "vgsys"
    raise IndexError("No suitable volume group found.")


class Monitor(object):
    def __init__(self):
        self.id = socket.gethostname()
        self.volume = XFSCephVolume("ceph-mon", f"/srv/ceph/mon/ceph-{self.id}")
        self.pid_file = f"/run/ceph/mon.{self.id}.pid"

    def activate(self):
        print(f"Activating MON {self.id}...")
        resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))

        self.volume.activate()
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

    def create(
        self,
        size="8g",
        lvm_vg=None,
        bootstrap_cluster=False,
        encrypt: bool = False,
    ):
        print(f"Creating MON {self.id}...")

        if not lvm_vg:
            lvm_vg = find_vg_for_mon()
        self.volume.create(lvm_vg, size, encrypt=encrypt)

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
        run.systemctl("stop", "fc-ceph-mon")
        try:
            self.deactivate()
        except Exception:
            pass

        run.ceph("mon", "remove", self.id)

        self.volume.purge(lv_only=True)
