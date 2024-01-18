import errno
import os
import resource
import sys
import threading
import time
import traceback
from subprocess import CalledProcessError
from typing import List, Optional

from fc.ceph.lvm import GenericCephVolume, GenericLogicalVolume, XFSCephVolume
from fc.ceph.util import kill, run

TiB = 1024**4


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
        self.local_osd_ids = GenericCephVolume.list_local_osd_ids()

    def _parse_ids(self, ids: str, allow_non_local=False) -> List[int]:
        if ids == "all":
            return self.local_osd_ids
        ids_all: set[int] = set((int(x) for x in ids.split(",")))
        non_local = set(ids_all) - set(self.local_osd_ids)
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
        return list(ids_all)

    def create_bluestore(
        self, device: str, wal: str, crush_location: str, encrypt: bool
    ):
        assert "=" in crush_location
        assert wal in ["internal", "external"]
        assert os.path.exists(device)

        print("Creating bluestore OSD ...")

        id_ = int(run.json.ceph("osd", "create")["osdid"])
        print(f"OSDID={id_}")

        osd = BlueStoreOSD(id_)
        # FIXME: for now just assume the presence of key files at default location
        osd.create(
            disk=device,
            encrypt=encrypt,
            wal_location=wal,
            crush_location=crush_location,
        )
        self._activate_single(osd, as_systemd_unit=False)

    def activate(self, ids: str, as_systemd_unit: bool = False):
        # special case optimisation
        nonblocking_start = ids == "all"
        ids_ = self._parse_ids(ids)

        if as_systemd_unit:
            if len(ids_) > 1:
                raise RuntimeError("Only single OSDs may be called as a unit.")
            id_ = ids_[0]
            osd = OSD(id_)
            try:
                self._activate_single(osd, as_systemd_unit)
            except Exception:
                traceback.print_exc()
        else:
            for id_ in ids_:
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
        entry point for low-level OSD operations that need to activate
        themselfs again, without having to know about systemd units
        """
        # this is then also allowed to bubble up errors

        if as_systemd_unit:
            resource.setrlimit(resource.RLIMIT_NOFILE, (270000, 270000))
            osd.activate()
        else:
            if nonblocking:
                run.systemctl("start", "--no-block", f"fc-ceph-osd@{osd.id}")
            else:
                run.systemctl("start", f"fc-ceph-osd@{osd.id}")

    def destroy(
        self,
        ids: str,
        no_safety_check: bool,
        strict_safety_check: bool,
        force_objectstore_type: Optional[str] = None,
    ):
        ids_ = self._parse_ids(ids, allow_non_local=f"DESTROY {ids}")

        for id_ in ids_:
            try:
                osd = OSD(id_, type=force_objectstore_type)
                osd.purge(no_safety_check, strict_safety_check)
            except Exception:
                traceback.print_exc()

    def deactivate(
        self,
        ids: str,
        as_systemd_unit: bool = False,
        flush: bool = False,
        no_safety_check: bool = False,
        strict_safety_check: bool = False,
    ):
        ids_ = self._parse_ids(ids)

        if as_systemd_unit:
            if len(ids_) > 1:
                raise RuntimeError("Only single OSDs may be called as a unit.")
            id_ = ids_[0]
            osd = OSD(id_)
            self._deactivate_single(osd, as_systemd_unit, flush)
        else:
            if no_safety_check:
                print("WARNING: Skipping stop safety check.")
            else:
                GenericOSD.run_safety_check(ids_, strict_safety_check)
            threads = []
            for id_ in ids_:
                try:
                    osd = OSD(id_)
                    thread = threading.Thread(
                        target=lambda: self._deactivate_single(
                            osd, as_systemd_unit, flush
                        ),
                        name=str(id_),
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
        ids_ = self._parse_ids(ids)

        for id_ in ids_:
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
        no_safety_check: bool,
        strict_safety_check: bool,
        encrypt: Optional[bool],
        # unused, keeping this for future new OSD types
        target_objectstore_type: Optional[str] = None,
    ):
        ids_ = self._parse_ids(ids)

        for id_ in ids_:
            try:
                osd = OSD(id_)
                osd.rebuild(
                    no_safety_check=no_safety_check,
                    target_objectstore_type=target_objectstore_type,
                    strict_safety_check=strict_safety_check,
                    encrypt=encrypt,
                )
            except Exception:
                traceback.print_exc()

    def prepare_journal(self, device: str):
        JournalVG.prepare_ext_vg(device)


def OSD(id_, type=None):
    # The set is ordered to prefer testing for BlueStore first because it
    # has a much much higher priority (read: ~100% chance).
    # Despite having removed FileStore, let's keep this abstraction in place
    # to be prepared for future OSD types.
    OSD_TYPES = {"bluestore": BlueStoreOSD}

    if type:
        return OSD_TYPES[type](id_)

    # XXX this doesn't detect inconsistent states, e.g. if an old journal
    # from filestore exists, but the OSD has been converted into bluestore
    # really.
    for osd_type in OSD_TYPES.values():
        if osd_type.is_responsible_for(id_):
            return osd_type(id_)

    raise RuntimeError(f"Could not detect OSD type for {id_}")


class JournalVG:
    """
    represents the LVM VG used for external WALs and mon/mgr data, as well as
    its associated operations
    """

    @staticmethod
    def prepare_ext_vg(device: str):
        """
        create the volume group used for placing external WALs or mon/mgr storage.
        """
        if not os.path.exists(device):
            print(f"Device does not exist: {device}")
        try:
            partition_table = run.json.sfdisk(device)["partitiontable"]
        except CalledProcessError as e:
            if b"does not contain a recognized partition table" not in e.stderr:
                # Not an empty disk, propagate the error
                raise
        else:
            if partition_table["partitions"]:
                print(
                    "Device already has a partition. Refusing to prepare journal VG."
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

    @staticmethod
    def get_largest_free() -> str:
        """Find suitable WAL VG: the one with the most free bytes"""
        return run.json.vgs(
            # fmt: off
            "-S", "vg_name=~^vgjnl[0-9][0-9]$",
            "-o", "vg_name,vg_free",
            "-O", "-vg_free",
            # fmt: on
        )[0]["vg_name"]


class WALVolume:
    def __init__(self, osd_id: str):
        self.osd_id = osd_id
        self.name = f"ceph-osd-{self.osd_id}-wal"
        self.internal_vg = f"vgosd-{self.osd_id}"
        self.lv = GenericLogicalVolume(self.name)
        # FIXME: the backup LV is conditional, do we really always want to create the object here?
        self.backup_lv = GenericLogicalVolume(
            f"ceph-osd-{self.osd_id}-wal-backup"
        )

    def create(self, disk: str, encrypt: bool, location: str):
        # External WAL
        if location == "external":
            lvm_wal_vg = JournalVG.get_largest_free()

            # OSDs with an external WAL still get a 1G LV on the OSD disk
            # itself to store a copy of the WAL, e.g. during offline disk
            # migration.
            print(f"Creating backup WAL on {self.name}-backup ...")
            self.backup_lv = GenericLogicalVolume.create(
                name=f"{self.name}-backup",
                vg_name=self.internal_vg,
                disk=disk,
                encrypt=encrypt,
                size="1G",
            )
        elif location == "internal":
            lvm_wal_vg = self.internal_vg
        else:
            raise ValueError(f"Invalid WAL type: {location}")

        print(f"Creating {location} WAL on {lvm_wal_vg} ...")
        self.lv = GenericLogicalVolume.create(
            name=f"{self.name}",
            vg_name=lvm_wal_vg,
            disk=disk,
            encrypt=encrypt,
            size="1G",
        )
        self.activate()

    def activate(self):
        self.lv.activate()

    @property
    def device(self):
        return self.lv.device

    @property
    def exists(self) -> bool:
        if self.lv:
            return self.lv.exists(self.name)
        return False

    @property
    def location(self):
        # let' use the existence of a WAL backup volume as a heuristic for an
        # external WAL. A cleaner implementation would be checking whether
        # self.lv has the same VG as internal_vg, but that requires publicly
        # exposing the VGs for all GenericVolume types.
        return "external" if self.has_wal_backup else "internal"

    @property
    def has_wal_backup(self):
        return bool(self.backup_lv)

    # TODO: unused so far, will be part of a dedicated inmigrate/ restore
    # operation when moving disks between hosts PL-130677
    def _restore_wal_backup(self):
        if self.has_wal_backup:
            print("Restoring external WAL from backup…")
            active_wal = self._locate_wal_lv()
            assert self.lvm_wal_backup_device != active_wal
            run.dd(
                f"if={self.lvm_wal_backup_device}",
                f"of={active_wal}",
                # ensure write barrier after WAL restore to ensure daemon start
                # only after successful persistence of data to disk
                f"oflag=fsync,nocache",
            )

    # TODO: unused so far, will be part of a dedicated inmigrate/ restore
    # operation when moving disks between hosts PL-130677
    def _create_wal_backup(self):
        if self.has_wal_backup:
            print("Flushing external WAL to backup…")
            active_wal = self._locate_wal_lv()
            assert self.lvm_wal_backup_device != active_wal
            run.dd(
                f"if={active_wal}",
                f"of={self.lvm_wal_backup_device}",
                # ensure write barrier after WAL restore to ensure daemon start
                # only after successful persistence of data to disk
                f"oflag=fsync,nocache",
            )

    def purge(self):
        if self.location == "external":
            self.lv.purge(lv_only=True)
            self.backup_lv.purge()
        else:
            self.lv.purge()


class BlockVolume(GenericCephVolume):
    def __init__(self, osd_id: str):
        self.osd_id = osd_id
        self.vg_name = f"vgosd-{self.osd_id}"
        self.name = f"ceph-osd-{self.osd_id}-block"
        self.lv = GenericLogicalVolume(self.name)

    def create(self, disk: str, encrypt: bool, size: str = "100%vg"):
        print(f"Creating block volume on {disk}...")
        self.lv = GenericLogicalVolume.create(
            name=self.name,
            vg_name=self.vg_name,
            disk=disk,
            encrypt=encrypt,
            size=size,
        )
        self.activate()

    @property
    def exists(self) -> bool:
        return self.lv.exists(self.name)

    @property
    def device(self) -> str:
        return self.lv.device

    def activate(self):
        self.lv.activate()

    def purge(self, lv_only=False):
        if self.lv:
            self.lv.purge(lv_only)


class GenericOSD(object):
    def __init__(self, id):
        self.id = id
        self.name = f"osd.{id}"
        self.pid_file = f"/run/ceph/osd.{self.id}.pid"

        self.data_volume = XFSCephVolume(
            f"ceph-osd-{self.id}", f"/srv/ceph/osd/ceph-{self.id}"
        )

    def activate(self):
        # needs to be fully overriden by OSD implementations
        raise NotImplementedError

    def deactivate(self):
        print(f"Stopping OSD {self.id} ...")
        kill(self.pid_file)

    def _set_crush_and_auth(
        self, volume: GenericCephVolume, crush_location: str
    ):
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
            "-i", f"{self.data_volume.mountpoint}/keyring",
            # fmt: on
        )

        # Compute CRUSH weight (1.0 == 1TiB)
        weight = float(volume.actual_size()) / TiB

        run.ceph("osd", "crush", "add", self.name, str(weight), crush_location)

    @staticmethod
    def run_safety_check(ids: List[int], strict_safety_check: bool):
        """
        Run a safety check on what would happen if the OSDs specified in `ids`
        became unavailable.

        By default, the `ceph osd ok-to-stop` is run and checks for remaining
        data availability.
        With `stric_safety_check`, the more strict `ceph osd safe-to-destroy`
        checks whether edundancy is affected in any ways.

        Raises a SystemExit if the check fails.
        """
        ids = map(str, ids)
        if strict_safety_check:
            try:
                run.ceph("osd", "safe-to-destroy", *ids)
            except CalledProcessError as e:
                print(
                    # fmt: off
                    "OSD not safe to destroy:", e.stderr,
                    "\nTo override this check, remove the `--strict-safety-check` flag. "
                    "This can lead to reduced data redundancy, still within safety margins."
                    # fmt: on
                )
                # ceph already returns ERRNO-style returncodes, so just pass them through
                sys.exit(e.returncode)
        else:
            try:
                run.ceph("osd", "ok-to-stop", *ids)
            except CalledProcessError as e:
                print(
                    # fmt: off
                    "OSD not okay to stop:", e.stderr,
                    "\nTo override this check, specify `--no-safety-check`. This can "
                    "cause data loss or cluster failure!!"
                    # fmt: on
                )
                # ceph already returns ERRNO-style returncodes, so just pass them through
                sys.exit(e.returncode)

    def purge(self, no_safety_check: bool, strict_safety_check: bool):
        """Deletes an osd, including removal of auth keys and crush map entry"""

        # Safety net
        if strict_safety_check and no_safety_check:
            print(
                "--no-safety-check and --strict-safety-check are incompatible flags."
            )
            sys.exit(10)
        if no_safety_check:
            print("WARNING: Skipping destroy safety check.")
        else:
            self.run_safety_check([self.id], strict_safety_check)

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

    def _collect_rebuild_information(self):
        """Helper function that collects the following information of an existing OSD
        for later rebuilding it, and returns them as a mapping:

            - device: the main blockdevice used by the osd
            - crush_location: where the OSD is located in the crush hierarchy
        """

        # retrieve current OSD properties before it gets destroyed
        # What's the physical disk?
        device = self.data_volume.lv.base_disk
        print(f"device={device}")

        # what's the crush location (host?)
        crush_location = "host={0}".format(
            run.json.ceph("osd", "find", str(self.id))["crush_location"]["host"]
        )

        print(f"--crush-location={crush_location}")

        return {
            "crush_location": crush_location,
            "device": device,
            "encrypt": self.data_volume.encrypted,
        }

    def _destroy_and_rebuild_to(
        self,
        target_osd_type: str,
        journal: str,
        no_safety_check: bool,
        strict_safety_check: bool,
        device: str,
        crush_location: str,
        encrypt: bool,
    ):
        """Helper function that destroys the current OSD and creates a new one with the
        specified parameters; useful for OSD rebuilding.
        """

        # `purge` also removes crush location and auth. A `destroy` would keep them, but
        # as we re-use the creation commands which always handle crush and auth as well,
        # for simplicity's sake this optimisation is not used.
        self.purge(no_safety_check, strict_safety_check)

        # This is an "interesting" turn-around ...
        manager = OSDManager()

        print("Creating OSD ...")
        print("Replicate with manual command:")

        if target_osd_type == "bluestore":
            print(
                f"fc-ceph osd create-bluestore {device} "
                f"--wal={journal} "
                f"--crush-location={crush_location} "
                f"{'--encrypt' if encrypt else '--no-encrypt'}"
            )

            manager.create_bluestore(
                device=device,
                wal=journal,
                crush_location=crush_location,
                encrypt=encrypt,
            )
        else:
            raise RuntimeError(
                f"object store type {target_osd_type} not supported"
            )

    def flush(self):
        pass


class BlueStoreOSD(GenericOSD):
    OBJECTSTORE_TYPE = "bluestore"

    def __init__(self, id):
        super().__init__(id)
        self.block_volume = BlockVolume(self.id)
        self.wal_volume = WALVolume(self.id)

    @staticmethod
    def is_responsible_for(id_):
        return WALVolume(id_).exists

    def create(
        self,
        disk: str,
        encrypt: bool,
        wal_location: str,
        crush_location: str,
    ):
        self.wal_volume.create(disk, encrypt, wal_location)
        self.data_volume.create(f"vgosd-{self.id}", "1g", disk, encrypt)
        self.block_volume.create(disk, encrypt)

        os.symlink(
            self.block_volume.device, f"{self.data_volume.mountpoint}/block"
        )

        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--mkfs", "--mkkey",
            "--osd-objectstore", "bluestore",
            "--osd-data", self.data_volume.mountpoint,
            "--bluestore-block-wal-path", self.wal_volume.device,
            # we experience auth issues at first mon contact *before* actually
            # creating the OSD and its own key, so only use locally available
            # config here
            "--no-mon-config",
            # fmt: on
        )
        self._set_crush_and_auth(self.block_volume, crush_location)

    def activate(self):
        print(f"Activating OSD {self.id}...")

        try:
            self.data_volume.activate()
            self.wal_volume.activate()
            self.block_volume.activate()
        except AttributeError:
            raise RuntimeError(
                "Failed to activate OSD volumes, they might not exist."
            )

        # Relocating OSDs: Create WAL LV if the symlink is broken
        # and fix the symlink (in case the VG name changed).
        run.ceph_osd(
            # fmt: off
            "-i", str(self.id),
            "--pid-file", self.pid_file,
            "--osd-data", self.data_volume.mountpoint,
            # fmt: on
        )

    def purge(self, no_safety_check, strict_safety_check):
        super().purge(no_safety_check, strict_safety_check)

        self.data_volume.purge(
            lv_only=True
        )  # involves umount, thus destroy first
        self.block_volume.purge(lv_only=True)
        self.wal_volume.purge()  # will also clean up the OSD VG

    def rebuild(
        self,
        no_safety_check: bool,
        strict_safety_check: bool,
        target_objectstore_type: Optional[str],
        encrypt: Optional[bool],
    ):
        """Fully destroy and create the OSD again with the same properties,
        optionally converting it to another OSD type.
        """
        target_osd_type = target_objectstore_type or self.OBJECTSTORE_TYPE

        print(
            f"Rebuilding OSD {self.id} from scratch "
            f"({'un' if not encrypt else ''}encrypted)"
        )

        oldosd_properties = self._collect_rebuild_information()

        if encrypt is not None:
            oldosd_properties["encrypt"] = encrypt

        journal = self.wal_volume.location
        print(f"--journal={journal}")

        self._destroy_and_rebuild_to(
            target_osd_type=target_osd_type,
            journal=journal,
            no_safety_check=no_safety_check,
            strict_safety_check=strict_safety_check,
            **oldosd_properties,
        )
