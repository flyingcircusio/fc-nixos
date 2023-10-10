import errno
import glob
import os
import re
import resource
import sys
import threading
import time
import traceback
from subprocess import CalledProcessError
from typing import Optional

from fc.ceph.util import kill, mount_status, run


def wait_for_clean_cluster():
    def _eval_health_check(status, checkname):
        """Helper function that returns True if the health check `checkname` is *not*
        okay in the status information passed as `status`.
        """
        try:
            check_unclean = (
                status["health"]["checks"][checkname]["severity"] != "HEALTH_OK"
            )
        except KeyError:
            # clean checks generally do not appear in output
            check_unclean = False
        return check_unclean

    while True:
        status = run.json.ceph("status")

        stopper_check_names = ["PG_AVAILABILITY", "PG_DEGRADED", "SLOW_OPS"]

        if not any(
            map(
                lambda checkn: _eval_health_check(status, checkn),
                stopper_check_names,
            )
        ):
            break

        # Don't be too fast here.
        time.sleep(5)


class OSDManager(object):
    def __init__(self):
        self.local_osd_ids = self._list_local_osd_ids()

    def _list_local_osd_ids(self):
        vgs = run.json.vgs("-S", r"vg_name=~^vgosd\-[0-9]+$")
        return [int(vg["vg_name"].replace("vgosd-", "", 1)) for vg in vgs]

    def _parse_ids(self, ids: str, allow_non_local=False):
        if ids == "all":
            return self.local_osd_ids
        ids = [int(x) for x in ids.split(",")]
        non_local = set(ids) - set(self.local_osd_ids)
        if non_local:
            if allow_non_local:
                print(
                    f"WARNING: I was asked to operate on "
                    f"non-local OSDs: {non_local}"
                )
                confirmation = input(f"To proceed enter `{allow_non_local}`: ")
                if confirmation != allow_non_local:
                    print("Confirmation was not given. Aborting.")
                    sys.exit(1)
            else:
                raise ValueError(
                    f"Refusing to operate on remote OSDs: {non_local}"
                )
        return ids

    def create_filestore(
        self, device: str, journal: str, journal_size: str, crush_location: str
    ):
        assert "=" in crush_location
        assert journal in ["internal", "external"]
        assert os.path.exists(device)

        print(
            "WARN: From Ceph Luminous on, we are deprecating the platform support "
            "for running FileStore OSDs.\n"
            "We may enable features not playing well with FileStore, among them:\n"
            "  - osd_scrub_auto_repair, this might spread data corruption in FileStore",
            end="\n\n",
        )

        print("Creating OSD ...")

        id_ = int(run.json.ceph("osd", "create")["osdid"])
        print(f"OSDID={id_}")

        osd = FileStoreOSD(id_)
        osd.create(device, journal, crush_location, journal_size)

    def create_bluestore(self, device, wal, crush_location):
        assert "=" in crush_location
        assert wal in ["internal", "external"]
        assert os.path.exists(device)

        print("Creating bluestore OSD ...")

        id_ = int(run.json.ceph("osd", "create")["osdid"])
        print(f"OSDID={id_}")

        osd = BlueStoreOSD(id_)
        osd.create(device, wal, crush_location)

    def activate(self, ids: str, as_systemd_unit: bool = False):
        # special case optimisation
        nonblocking_start = ids == "all"
        ids = self._parse_ids(ids)

        if as_systemd_unit:
            if len(ids) > 1:
                raise RuntimeError("Only single OSDs may be called as a unit.")
            id_ = ids[0]
            osd = OSD(id_)
            try:
                self._activate_single(osd, as_systemd_unit)
            except Exception:
                traceback.print_exc()
        else:
            for id_ in ids:
                osd = OSD(id_)
                self._activate_single(
                    osd, as_systemd_unit=False, nonblocking=nonblocking_start
                )

    def _activate_single(
        self,
        osd: "GenericOSD",
        as_systemd_unit: bool = False,
        nonblocking: bool = False,
    ):
        """
        entry point for low-level OSD operations that need to activate themselfs again,
        without having to know about systemd units"""
        # this is then also allowed to bubble up errors

        if as_systemd_unit:
            osd.activate()
        else:
            if nonblocking:
                run.systemctl("start", "--no-block", f"fc-ceph-osd@{osd.id}")
            else:
                run.systemctl("start", f"fc-ceph-osd@{osd.id}")

    def destroy(
        self,
        ids: str,
        unsafe_destroy: bool,
        strict_safety_check: bool,
        force_objectstore_type: Optional[str] = None,
    ):
        ids = self._parse_ids(ids, allow_non_local=f"DESTROY {ids}")

        for id_ in ids:
            try:
                osd = OSD(id_, type=force_objectstore_type)
                osd.purge(unsafe_destroy, strict_safety_check)
            except Exception:
                traceback.print_exc()

    def deactivate(
        self, ids: str, as_systemd_unit: bool = False, flush: bool = False
    ):
        ids = self._parse_ids(ids)

        if as_systemd_unit:
            if len(ids) > 1:
                raise RuntimeError("Only single OSDs may be called as a unit.")
            id_ = ids[0]
            osd = OSD(id_)
            self._deactivate_single(osd, as_systemd_unit, flush)
        else:
            threads = []
            for id_ in ids:
                try:
                    osd = OSD(id_)
                    thread = threading.Thread(
                        target=lambda: self._deactivate_single(
                            osd, as_systemd_unit, flush
                        ),
                        name=id_,
                    )
                    thread.start()
                    threads.append(thread)
                except Exception:
                    traceback.print_exc()

            for thread in threads:
                thread.join()

            deactivated_osds = ", ".join([str(t.name) for t in threads])
            print("Successfully deactivated OSDs", deactivated_osds)

    def _deactivate_single(
        self,
        osd: "GenericOSD",
        as_systemd_unit: bool = False,
        flush: bool = False,
    ):
        """
        entry point for low-level OSD operations that need to activate themselfs again,
        without having to know about systemd units"""
        if as_systemd_unit:
            osd.deactivate()
        else:
            run.systemctl("stop", f"fc-ceph-osd@{osd.id}")
        if flush:
            osd.flush()

    def reactivate(self, ids: str):
        ids = self._parse_ids(ids)

        for id_ in ids:
            osd = OSD(id_)
            wait_for_clean_cluster()
            try:
                self._deactivate_single(osd, as_systemd_unit=False, flush=False)
                self._activate_single(osd, as_systemd_unit=False)
            except Exception:
                traceback.print_exc()

    def rebuild(
        self,
        ids: str,
        journal_size: str,
        unsafe_destroy: bool,
        strict_safety_check: bool,
        target_objectstore_type: Optional[str] = None,
    ):
        ids = self._parse_ids(ids)

        for id_ in ids:
            try:
                osd = OSD(id_)
                osd.rebuild(
                    journal_size=journal_size,
                    unsafe_destroy=unsafe_destroy,
                    target_objectstore_type=target_objectstore_type,
                    strict_safety_check=strict_safety_check,
                )
            except Exception:
                traceback.print_exc()

    def prepare_journal(self, device: str):
        if not os.path.exists(device):
            print(f"Device does not exist: {device}")
        try:
            partition_table = run.json.sfdisk(device)["partitiontable"]
        except Exception as e:
            if b"does not contain a recognized partition table" not in e.stderr:
                # Not an empty disk, propagate the error
                raise
        else:
            if partition_table["partitions"]:
                print(
                    "Device already has a partition. "
                    "Refusing to prepare journal VG."
                )
                sys.exit(1)

        ids = set()
        for journal_vg in run.json.vgs("-S", r"vg_name=~^vgjnl[0-9][0-9]$"):
            id_ = int(journal_vg["vg_name"].replace("vgjnl", ""), 10)
            ids.add(id_)

        # find the first free number
        for id_ in range(99):
            if id_ not in ids:
                break
        else:
            raise ValueError("No free journal ID 0<=id<=99 found.")

        jnl_vg = "vgjnl{:02d}".format(id_)

        run.sgdisk("-Z", device)
        run.sgdisk("-a", "8192", "-n", "1:0:0", "-t", "1:8e00", device)

        for partition in [f"{device}1", f"{device}p1"]:
            if os.path.exists(partition):
                break
        else:
            raise RuntimeError(f"Could not find partition for PV on {device}")

        run.pvcreate(partition)
        run.vgcreate(jnl_vg, partition)


def OSD(id_, type=None):
    if not type:
        mountpoint = GenericOSD.ensure_osd_data_dir_is_mounted(id_)
        with open(f"{mountpoint}/type") as f:
            type = f.read().strip()

    OSD_TYPES = {"filestore": FileStoreOSD, "bluestore": BlueStoreOSD}
    return OSD_TYPES[type](id_)


class GenericOSD(object):
    MKFS_XFS_OPTS = ["-m", "crc=1,finobt=1", "-i", "size=2048", "-K"]
    MOUNT_XFS_OPTS = "nodev,nosuid,noatime,nodiratime,logbsize=256k"

    DATA_VOLUME_SIZE = None

    def __init__(self, id):
        self.id = id

        self.datadir = f"/srv/ceph/osd/ceph-{self.id}"
        self.lvm_vg = f"vgosd-{self.id}"
        self.lvm_vg_esc = re.escape(self.lvm_vg)

        self.lvm_lv = f"ceph-osd-{self.id}"
        self.lvm_data_device = f"/dev/{self.lvm_vg}/{self.lvm_lv}"

        self.pid_file = f"/run/ceph/osd.{self.id}.pid"

        self.name = f"osd.{id}"

    @classmethod
    def ensure_osd_data_dir_is_mounted(cls, id_):
        mountpoint = f"/srv/ceph/osd/ceph-{id_}"
        data_device = f"/dev/vgosd-{id_}/ceph-osd-{id_}"
        expected_mapped_name = f"vgosd--{id_}-ceph--osd--{id_}"

        mount_device = mount_status(mountpoint)

        if mount_device:
            if mount_device != expected_mapped_name:
                raise RuntimeError(
                    f"Mountpoint is using unexpected device `{mount_device}`."
                )
        else:
            if not os.path.exists(mountpoint):
                os.makedirs(mountpoint)
            run.mount(
                # fmt: off
                "-t", "xfs", "-o", cls.MOUNT_XFS_OPTS,
                data_device, mountpoint,
                # fmt: on
            )
        return mountpoint

    def activate(self):
        print(f"Activating OSD {self.id}...")

        self.ensure_osd_data_dir_is_mounted(self.id)

        resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))

    def deactivate(self):
        print(f"Stopping OSD {self.id} ...")
        kill(self.pid_file)

    def create(
        self, device, journal_location, crush_location, journal_size=None
    ):
        """Create an OSD and everything necessary for doing so:
            - set up physical devices and volumes
            - create journals or write-ahead logs
            - incorporation into ceph cluster, crush map, auth

        This follows a top-down design, with the common operations being defined in
        this parent function, and specialised sub-operations being called as hook
        functions that can implement specialised behaviour:
            - _create_journal
            - _create_post_and_register
            - _create_crush_and_auth

        params:
            - device: path to blockdevice used for main OSD components
            - journal_location: one of ("external"|"internal")
            - crush_location: string describing the crush location as taken by
              `ceph osd crush`
            - journal_size: string of numeric size and a unit suffix"""

        # 1. prepare physical volumes and mountpoints
        if not os.path.exists(self.datadir):
            os.makedirs(self.datadir)

        run.sgdisk("-Z", device)
        run.sgdisk("-a", "8192", "-n", "1:0:0", "-t", "1:8e00", device)

        for partition in [f"{device}1", f"{device}p1"]:
            if os.path.exists(partition):
                break
        else:
            raise RuntimeError(f"Could not find partition for PV on {device}")

        run.pvcreate(partition)
        run.vgcreate(self.lvm_vg, partition)

        # 2. create journal or WAL
        journal_lvm_path = self._create_journal(journal_location, journal_size)

        # 3. Create OSD LV on remainder of the VG
        run.lvcreate(
            # fmt: off
            "-W", "y", "-y",
            self.DATA_VOLUME_SIZE,
            f"-n{self.lvm_lv}",
            self.lvm_vg,
            # fmt: on
        )

        # Create OSD filesystem
        run.mkfs_xfs(
            "-f", "-L", self.name, *self.MKFS_XFS_OPTS + [self.lvm_data_device]
        )
        run.sync()
        run.mount(
            # fmt: off
            "-t", "xfs", "-o", self.MOUNT_XFS_OPTS,
            self.lvm_data_device, self.datadir,
            # fmt: on
        )

        # 4. create additional block LVs and register to ceph cluster
        self._create_post_and_register(journal_lvm_path)

        # 5. create crush and auth
        self._create_crush_and_auth(self.data_lv, crush_location)

        # 6. activate OSD
        osdmanager = OSDManager()
        # rebuilds are never triggered from inside a systemd unit
        osdmanager._activate_single(self, as_systemd_unit=False)

    def _create_journal(journal_location, journal_size):
        """Hook function for creating journal/ WAL/ other similar devices.
        Must be implemented and overriden by the subclass OSD.
        Returns: string path to a journal LVM volume

        params:
            - journal_location: one of ("external"|"internal")
            - journal_size: string of numeric size and a unit suffix"""
        raise NotImplementedError()

    def _create_post_and_register(journal_lvm_path):
        """Create additional block LVs for the OSD, other than the main OSD filesystem,
        and initialise them.
        After that, register the new OSD at the ceph cluster.
        Must be implemented and overriden by the subclass OSD.

        params:
            - journal_lvm_path: string path to a journal/WAL/… LVM volume"""
        raise NotImplementedError()

    def _create_crush_and_auth(self, volume, crush_location):
        """Creates authentication key for new OSD and adds it to crush map with correct
        weights.
        Has a usable default implementation.

        params:
            - volume: main data volume
            - crush_location: string describing the crush location as taken by
              `ceph osd crush`
        """
        run.ceph(
            # fmt: off
            "auth", "add", self.name,
            "osd", "allow *",
            "mon", "allow rwx",
            "-i", f"{self.datadir}/keyring",
            # fmt: on
        )

        # Compute CRUSH weight (1.0 == 1TiB)
        lvm_lv_esc = re.escape(volume)
        lv = run.json.lvs("-S", f"lv_name=~^{lvm_lv_esc}$", "-o", "lv_size")[0]
        size = lv["lv_size"]
        weight = float(size) / 1024**4

        run.ceph("osd", "crush", "add", self.name, str(weight), crush_location)

    def purge(self, unsafe_destroy: bool, strict_safety_check: bool):
        """Deletes an osd, including removal of auth keys and crush map entry"""

        # Safety net
        if strict_safety_check and unsafe_destroy:
            print(
                "--unsafe-destroy and --strict-safety-check are incompatible flags."
            )
            sys.exit(10)
        if unsafe_destroy:
            print("WARNING: Skipping destroy safety check.")
        elif strict_safety_check:
            try:
                run.ceph("osd", "safe-to-destroy", str(self.id))
            except CalledProcessError as e:
                print(
                    # fmt: off
                    "OSD not safe to destroy:", e.stderr,
                    "\nTo override this check, remove the `--strict-safety-check` flag. "
                    "This can lead to reduced data redundancy, still within safety margins."
                    # fmt: on
                )
                # do we have some generic or specific error return codes?
                sys.exit(10)
        else:
            try:
                run.ceph("osd", "ok-to-stop", str(self.id))
            except CalledProcessError as e:
                print(
                    # fmt: off
                    "OSD not okay to stop:", e.stderr,
                    "\nTo override this check, specify `--unsafe-destroy`. This can "
                    "cause data loss or cluster failure!!"
                    # fmt: on
                )
                # do we have some generic or specific error return codes?
                sys.exit(10)

        print(f"Destroying OSD {self.id} ...")
        osdmanager = OSDManager()

        try:
            # purging is never done from inside a single systemd unit, thus osd
            # deactivation is being left to the OSD manager
            osdmanager._deactivate_single(
                self, as_systemd_unit=False, flush=False
            )
        except Exception as e:
            print(e)

        # Delete OSD object
        while True:
            try:
                run.ceph("osd", "purge", str(self.id), "--yes-i-really-mean-it")
            except CalledProcessError as e:
                # OSD is still shutting down, keep trying.
                if e.returncode == errno.EBUSY:
                    time.sleep(1)
                    continue
                raise
            break

        if os.path.exists(self.datadir):
            run.umount("-f", self.datadir, check=False)
            os.rmdir(self.datadir)

        # Delete LVs
        run.wipefs("-q", "-a", self.lvm_data_device, check=False)
        run.lvremove("-f", self.lvm_data_device, check=False)

        try:
            pv = run.json.pvs("-S", f"vg_name=~^{self.lvm_vg_esc}$")[0]
        except IndexError:
            pass
        else:
            run.vgremove("-f", self.lvm_vg, check=False)
            run.pvremove(pv["pv_name"], check=False)

        # Force remove old mapper files
        delete_paths = (
            glob.glob(f"/dev/vgosd-{self.id}/*")
            + glob.glob(f"/dev/mapper/vgosd--{self.id}-*")
            + [f"/dev/vgosd-{self.id}"]
        )
        for x in delete_paths:
            if not os.path.exists(x):
                continue
            print(x)
            if os.path.isdir(x):
                os.rmdir(x)
            else:
                os.unlink(x)

    def _collect_rebuild_information(self):
        """Helper function that collects the following information of an existing OSD
        for later rebuilding it, and returns them as a mapping:

            - device: the main blockdevice used by the osd
            - crush_location: where the OSD is located in the crush hierarchy
        """

        # retrieve current OSD properties before it gets destroyed
        # What's the physical disk?
        pvs = run.json.pvs("-S", f"vg_name={self.lvm_vg}", "--all")
        if not len(pvs) == 1:
            raise ValueError(
                f"Unexpected number of PVs in OSD's RG: {len(pvs)}"
            )
        pv = pvs[0]["pv_name"]
        # Find the parent
        for candidate in run.json.lsblk_linear(pv, "-o", "name,pkname"):
            if candidate["name"] == pv.split("/")[-1]:
                device = "/".join(["", "dev", candidate["pkname"]])
                break
        else:
            raise ValueError(f"Could not find parent for PV: {pv}")
        print(f"device={device}")

        # what's the crush location (host?)
        crush_location = "host={0}".format(
            run.json.ceph("osd", "find", str(self.id))["crush_location"]["host"]
        )

        print(f"--crush-location={crush_location}")

        return {
            "crush_location": crush_location,
            "device": device,
        }

    def _destroy_and_rebuild_to(
        self,
        target_osd_type: str,
        journal: str,
        journal_size: str,
        unsafe_destroy: bool,
        strict_safety_check: bool,
        device: str,
        crush_location: str,
    ):
        """Helper function that destroys the current OSD and creates a new one with the
        specified parameters; useful for OSD rebuilding.
        """

        # `purge` also removes crush location and auth. A `destroy` would keep them, but
        # as we re-use the creation commands which always handle crush and auth as well,
        # for simplicity's sake this optimisation is not used.
        self.purge(unsafe_destroy, strict_safety_check)

        # This is an "interesting" turn-around ...
        manager = OSDManager()

        print("Creating OSD ...")
        print("Replicate with manual command:")

        if target_osd_type == "bluestore":
            print(
                f"fc-ceph osd create-bluestore {device} "
                f"--wal={journal} "
                f"--crush-location={crush_location}"
            )

            manager.create_bluestore(device, journal, crush_location)
        elif target_osd_type == "filestore":
            print(
                f"fc-ceph osd create-filestore {device} "
                f"--journal={journal} "
                f"--journal-size={journal_size} "
                f"--crush-location={crush_location}"
            )
            manager.create_filestore(
                device, journal, journal_size, crush_location
            )
        else:
            raise RuntimeError(
                f"object store type {target_osd_type} not supported"
            )


class FileStoreOSD(GenericOSD):
    OBJECTSTORE_TYPE = "filestore"
    DATA_VOLUME_SIZE = "-l100%vg"

    def __init__(self, id):
        super().__init__(id)

        self.lvm_journal = f"ceph-jnl-{self.id}"
        self.lvm_journal_esc = re.escape(self.lvm_journal)

    def _locate_journal_lv(self):
        try:
            lvm_journal_vg = run.json.lvs(
                "-S",
                f"lv_name=~^{self.lvm_journal_esc}$",
            )[0]["vg_name"]
            return f"/dev/{lvm_journal_vg}/{self.lvm_journal}"
        except IndexError:
            raise ValueError(
                f"No journal found for OSD {self.id} - "
                "does this OSD exist on this host?"
            )

    @property
    def data_lv(self):
        return self.lvm_lv

    def activate(self):
        super().activate()

        # Check VG for journal
        lvm_journal = self._locate_journal_lv()

        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--pid-file", self.pid_file,
            "--osd-data", self.datadir,
            "--osd-journal", lvm_journal
            # fmt: on
        )

    def deactivate(self):
        # deactivate (shutdown osd, remove things but don't delete it, make
        # the osd able to be relocated somewhere else)
        super().deactivate()

    def flush(self):
        print(f"Flushing journal for OSD {self.id} ...")
        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--flush-journal",
            "--osd-data", self.datadir,
            "--osd-journal", self._locate_journal_lv(),
            # fmt: on
        )

    def _create_journal(self, journal, journal_size):
        # External journal
        if journal == "external":
            # - Find suitable journal VG: the one with the most free bytes
            lvm_journal_vg = run.json.vgs(
                # fmt: off
                "-S", "vg_name=~^vgjnl[0-9][0-9]$",
                "-o", "vg_name,vg_free",
                "-O", "-vg_free",
                # fmt: on
            )[0]["vg_name"]
            print(f"Creating external journal on {lvm_journal_vg} ...")
            run.lvcreate(
                # fmt: off
                "-W", "y", "-y",
                f"-L{journal_size}", f"-n{self.lvm_journal}",
                lvm_journal_vg,
                # fmt: on
            )
            lvm_journal_path = f"/dev/{lvm_journal_vg}/{self.lvm_journal}"
        elif journal == "internal":
            print(f"Creating internal journal on {self.lvm_vg} ...")
            run.lvcreate(
                # fmt: off
                "-W", "y", "-y",
                f"-L{journal_size}", f"-n{self.lvm_journal}",
                self.lvm_vg,
                # fmt: on
            )
            lvm_journal_path = f"/dev/{self.lvm_vg}/{self.lvm_journal}"
        else:
            raise ValueError(f"Invalid journal type: {journal}")

        return lvm_journal_path

    def _create_post_and_register(self, lvm_journal_path):
        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--mkfs", "--mkkey", "--mkjournal",
            "--osd-objectstore", "filestore",
            "--osd-data", self.datadir,
            "--osd-journal", lvm_journal_path,
            # we experience auth issues at first mon contact *before* actually creating
            # the OSD and its own key, so only use locally available config here
            "--no-mon-config",
            # fmt: on
        )

    def purge(self, unsafe_destroy, strict_safety_check):
        super().purge(unsafe_destroy, strict_safety_check)

        # Try deleting an external journal. The internal journal was already
        # deleted during the generic destroy of the VG.
        try:
            run.lvremove("-f", self._locate_journal_lv(), check=False)
        except ValueError:
            pass

    def rebuild(
        self,
        journal_size: str,
        unsafe_destroy: bool,
        strict_safety_check: bool,
        target_objectstore_type: Optional[str],
    ):
        """Fully destroy and create the FileStoreOSD again with the same properties,
        optionally converting it to another OSD type.
        """
        target_osd_type = target_objectstore_type or self.OBJECTSTORE_TYPE

        print(
            f"Rebuilding {self.OBJECTSTORE_TYPE} OSD {self.id} from scratch "
            + f"to {target_osd_type}"
        )

        oldosd_properties = self._collect_rebuild_information()

        # NOTE: If the existing filestore OSD was created with a non-default journal
        # size, this is not discovered and re-used. For now, non-default journal sizes
        # always need to be specified explicitly.
        # As the jewel code did not read existing journal size,
        # I'll keep it as is for now.

        # this is filestore/ bluestore specific
        # Is the journal internal or external?
        lvs = run.json.lvs("-S", f"vg_name={self.lvm_vg}")
        if len(lvs) == 1:
            journal = "external"
        elif len(lvs) == 2:
            journal = "internal"
        else:
            raise ValueError(
                f"Unexpected number of LVs in OSD's RG: {len(lvs)}"
            )
        print(f"--journal={journal}")

        self._destroy_and_rebuild_to(
            target_osd_type=target_osd_type,
            journal=journal,
            journal_size=journal_size,
            unsafe_destroy=unsafe_destroy,
            strict_safety_check=strict_safety_check,
            **oldosd_properties,
        )


class BlueStoreOSD(GenericOSD):
    OBJECTSTORE_TYPE = "bluestore"
    DATA_VOLUME_SIZE = "-L1g"

    def __init__(self, id):
        super().__init__(id)
        self.lvm_block_lv = f"ceph-osd-{self.id}-block"
        self.lvm_wal_lv = f"ceph-osd-{self.id}-wal"
        self.lvm_wal_backup_lv = f"ceph-osd-{self.id}-wal-backup"
        self.lvm_wal_esc = re.escape(self.lvm_wal_lv)
        self.lvm_block_device = f"/dev/{self.lvm_vg}/{self.lvm_block_lv}"
        self.lvm_wal_backup_device = (
            f"/dev/{self.lvm_vg}/{self.lvm_wal_backup_lv}"
        )

    def _locate_wal_lv(self):
        try:
            lvm_wal_vg = run.json.lvs("-S", f"lv_name=~^{self.lvm_wal_esc}$",)[
                0
            ]["vg_name"]
            return f"/dev/{lvm_wal_vg}/{self.lvm_wal_lv}"
        except IndexError:
            raise ValueError(
                f"No WAL found for OSD {self.id} - "
                "does this OSD exist on this host?"
            )

    @property
    def _has_wal_backup(self):
        return os.path.exists(self.lvm_wal_backup_device)

    # TODO: unused so far, will be part of a dedicated inmigrate/ restore operation
    # when moving disks between hosts PL-130677
    def _restore_wal_backup(self):
        if self._has_wal_backup:
            print("Restoring external WAL from backup…")
            active_wal = self._locate_wal_lv()
            assert self.lvm_wal_backup_device != active_wal
            run.dd(
                f"if={self.lvm_wal_backup_device}",
                f"of={active_wal}",
                # ensure write barrier after WAL restore to ensure daemon start only
                # after successful persistence of data to disk
                f"oflag=fsync,nocache",
            )

    # TODO: unused so far, will be part of a dedicated inmigrate/ restore operation
    # when moving disks between hosts PL-130677
    def _create_wal_backup(self):
        if self._has_wal_backup:
            print("Flushing external WAL to backup…")
            active_wal = self._locate_wal_lv()
            assert self.lvm_wal_backup_device != active_wal
            run.dd(
                f"if={active_wal}",
                f"of={self.lvm_wal_backup_device}",
                # ensure write barrier after WAL restore to ensure daemon start only
                # after successful persistence of data to disk
                f"oflag=fsync,nocache",
            )

    @property
    def data_lv(self):
        return self.lvm_block_lv

    def activate(self):
        super().activate()

        # Relocating OSDs: Create WAL LV if the symlink is broken
        # and fix the symlink (in case the VG name changed).
        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--pid-file", self.pid_file,
            "--osd-data", self.datadir,
            # fmt: on
        )

    def deactivate(self):
        # deactivate (shutdown osd, remove things but don't delete it
        # TODO: this is not sufficient for migrating the OSD to another host if it has
        # an external WAL, that requires a manual outmigration command PL-130677
        super().deactivate()

    def flush(self):
        # trivial journal flushing is not implemented for Bluestore OSDs,
        # WAL management is a bit more complex
        pass

    def _create_journal(self, wal, __size_is_ignored):
        # External WAL
        if wal == "external":
            # - Find suitable WAL VG: the one with the most free bytes
            lvm_wal_vg = run.json.vgs(
                # fmt: off
                "-S", "vg_name=~^vgjnl[0-9][0-9]$",
                "-o", "vg_name,vg_free",
                "-O", "-vg_free",
                # fmt: on
            )[0]["vg_name"]

            # OSDs with an external WAL still get a 1G LV on the OSD disk itself to store
            # a copy of the WAL, e.g. during offline disk migration.
            print(f"Creating backup WAL on {self.lvm_wal_backup_lv} ...")
            run.lvcreate(
                # fmt: off
                "-W", "y", "-y",
                "-L1G", f"-n{self.lvm_wal_backup_lv}",
                self.lvm_vg,
                # fmt: on
            )
        elif wal == "internal":
            lvm_wal_vg = self.lvm_vg
        else:
            raise ValueError(f"Invalid WAL type: {wal}")

        print(f"Creating {wal} WAL on {lvm_wal_vg} ...")
        run.lvcreate(
            # fmt: off
            "-W", "y", "-y",
            "-L1G", f"-n{self.lvm_wal_lv}",
            lvm_wal_vg,
            # fmt: on
        )
        lvm_wal_path = f"/dev/{lvm_wal_vg}/{self.lvm_wal_lv}"

        return lvm_wal_path

    def _create_post_and_register(self, lvm_wal_path):
        # Create OSD BLOCK LV for the actual data on remainder of the VG
        run.lvcreate(
            "-W", "y", "-y", "-l100%vg", f"-n{self.lvm_block_lv}", self.lvm_vg
        )

        # We can pass the WAL path to the ceph-osd --mkfs call, but the
        # block device appears to not have an option and needs to be primed
        # externally.
        os.symlink(self.lvm_block_device, f"{self.datadir}/block")

        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--mkfs", "--mkkey",
            "--osd-objectstore", "bluestore",
            "--osd-data", self.datadir,
            "--bluestore-block-wal-path", lvm_wal_path,
            # we experience auth issues at first mon contact *before* actually creating
            # the OSD and its own key, so only use locally available config here
            "--no-mon-config",
            # fmt: on
        )

    def purge(self, unsafe_destroy, strict_safety_check):
        super().purge(unsafe_destroy, strict_safety_check)

        try:
            run.lvremove("-f", self._locate_wal_lv(), check=False)
            if self._has_wal_backup:
                run.lvremove("-f", self.lvm_wal_backup_lv, check=False)
        except ValueError:
            pass

    def rebuild(
        self,
        journal_size: str,
        unsafe_destroy: bool,
        strict_safety_check: bool,
        target_objectstore_type: Optional[str],
    ):
        """Fully destroy and create the FileStoreOSD again with the same properties,
        optionally converting it to another OSD type.
        """
        target_osd_type = target_objectstore_type or self.OBJECTSTORE_TYPE

        print(
            f"Rebuilding {self.OBJECTSTORE_TYPE} OSD {self.id} from scratch "
            + f"to {target_osd_type}"
        )

        oldosd_properties = self._collect_rebuild_information()

        # this is filestore/ bluestore specific: Bluestore always creates one more
        # additional LV `ceph-osd-X-block`
        # Is the journal internal or external?

        # heuristic: Having a backup WAL volume indicates an external journal, otherwise
        # assume an external one
        if self._has_wal_backup:
            journal = "external"
        else:
            journal = "internal"
        print(f"--journal={journal}")

        self._destroy_and_rebuild_to(
            target_osd_type=target_osd_type,
            journal=journal,
            journal_size=journal_size,
            unsafe_destroy=unsafe_destroy,
            strict_safety_check=strict_safety_check,
            **oldosd_properties,
        )
