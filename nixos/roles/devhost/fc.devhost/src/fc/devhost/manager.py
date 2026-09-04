import datetime
import fcntl
import hashlib
import ipaddress
import json
import os
import shutil
import socket
import subprocess
import tempfile
import textwrap
import time
from pathlib import Path
from typing import Any, cast

import psutil
import requests
from tabulate import tabulate

from fc.devhost.qmp import QEMUMonitorProtocol, QMPConnectError
from fc.devhost.timeout import TimeOut

MAX_VM_ID = 1024
NETWORK = ipaddress.ip_network("10.12.0.0/16")
CONFIG_DIR = Path("/etc/devhost/vm-configs")
VM_BASE_IMAGE_DIR = Path("/var/lib/devhost/base-images")
VM_DATA_DIR = Path("/var/lib/devhost/vms")
LOCKFILE_PATH = "/run/fc-devhost-vm"

MONTH = 60 * 60 * 24 * 30


def merge_dicts(
    current: dict[Any, Any],
    update: dict[Any, Any],
) -> dict[Any, Any]:
    """Recursively merge update into current dict.

    Keys from update replace keys in current. Container values (lists, sets,
    etc.) are replaced entirely, not merged. Only dicts are merged recursively.
    """
    result = current.copy()
    for key, value in update.items():
        if (
            key in result
            and isinstance(result[key], dict)
            and isinstance(value, dict)
        ):
            result[key] = merge_dicts(result[key], cast(dict[Any, Any], value))
        else:
            result[key] = value
    return result


def parse_disk_size(size_str):
    """Parse disk size string (e.g., '25G', '1024M') and return size in bytes."""
    if not size_str:
        raise ValueError("Disk size cannot be empty")

    size_str = size_str.strip().upper()

    # Handle different size units
    multipliers = {
        "B": 1,
        "K": 1024,
        "M": 1024**2,
        "G": 1024**3,
        "T": 1024**4,
    }

    # Extract number and unit
    if size_str[-1] in multipliers:
        unit = size_str[-1]
        number_str = size_str[:-1]
    else:
        # Assume bytes if no unit specified
        unit = "B"
        number_str = size_str

    try:
        number = float(number_str)
        if number < 0:
            raise ValueError(f"Disk size cannot be negative: {size_str}")
    except ValueError as e:
        raise ValueError(f"Invalid disk size format: {size_str}") from e

    return int(number * multipliers[unit])


def run(*args, **kwargs):
    kwargs["check"] = True
    return subprocess.run(args, **kwargs)


def list_all_vm_configs():
    for vm in CONFIG_DIR.glob("*.json"):
        yield json.load(open(vm))


def check_if_nbd_device_is_used(number):
    with open(f"/sys/class/block/nbd{number}/size", "r") as f:
        return f.read() != "0"


def write_nix_file(nix_file_path, cfg):
    # Nixify the alias list
    nix_aliases = " ".join(map(lambda x: f'"{x}"', cfg["aliases"]))
    with open(nix_file_path, mode="w") as f:
        f.write(
            textwrap.dedent(
                f"""\
        # DO NOT TOUCH!
        # Managed by fc-devhost
        {{ ... }}: {{
          flyingcircus.roles.devhost.virtualMachines = {{
            "{cfg["name"]}" = {{
              enable = {"true" if cfg["online"] else "false"};
              id = {cfg["id"]};
              memory = "{cfg["memory"]}";
              cpu = {cfg["cpu"]};
              srvIp = "{cfg["srv-ip"]}";
              srvMac = "{cfg["srv-mac"]}";
              aliases = [ {nix_aliases} ];
            }};
          }};
        }}
        """
            )
        )


def generate_enc(cfg: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": cfg["name"],
        "parameters": {
            "cores": cfg["cpu"],
            "environment": "dev-vm",
            "interfaces": {
                "srv": {
                    "bridged": False,
                    "gateways": {
                        NETWORK.exploded: NETWORK[1].exploded,
                    },
                    "mac": cfg["srv-mac"],
                    "networks": {
                        NETWORK.exploded: [cfg["srv-ip"]],
                    },
                }
            },
            "location": cfg["location"],
            "memory": cfg["memory"],
        },
    }


class Manager:
    name: str  # Name of the managed VM
    cfg: dict[str, Any]

    def __init__(self, name: str):
        self.name = name
        self.cfg = {}

    @property
    def nix_file(self):
        return CONFIG_DIR / f"{self.name}.nix"

    @property
    def config_file(self):
        return CONFIG_DIR / f"{self.name}.json"

    @property
    def data_dir(self):
        return VM_DATA_DIR / self.name

    @property
    def image_file(self):
        return VM_DATA_DIR / self.name / "rootfs.qcow2"

    @property
    def image_file_tmp(self):
        return VM_DATA_DIR / self.name / "rootfs.qcow2.tmp"

    @property
    def qmp_sock(self):
        return VM_DATA_DIR / self.name / "qmp.sock"

    @property
    def pid_file(self):
        return VM_DATA_DIR / self.name / "pid"

    @property
    def lockfile(self):
        return open(LOCKFILE_PATH, "a+")

    __qmp = None

    @property
    def qmp(self):
        if self.__qmp is None:
            qmp = QEMUMonitorProtocol(str(self.qmp_sock))
            qmp.settimeout(5 * 60)
            try:
                qmp.connect()
            except socket.error:
                # We do not log this as this does happen quite regularly and
                # is usually fine as the VM wasn't started (yet).
                pass
            else:
                self.__qmp = qmp
        return self.__qmp

    def destroy(self, location=None):
        print("Assuming devhost lock ...")
        fcntl.flock(self.lockfile, fcntl.LOCK_EX)
        # We want do destroy everything existing for a VM.
        # If something in the provisioning failed, there might not be all files.
        print(f"Removing {self.name} from NixOS config ...")
        if os.path.isfile(self.config_file):
            self.config_file.unlink()
        if os.path.isfile(self.nix_file):
            self.nix_file.unlink()
        shutil.rmtree(self.data_dir, ignore_errors=True)
        print(f"Deleting {self.name} data ...")
        run("fc-manage", "switch")

    def ensure(
        self,
        cpu,
        memory,
        aliases,
        location,
        hydra_eval=None,
        image_url=None,
        channel_url: str = "",
        update_channel: bool = True,
        disk_size=None,
    ):
        print("Assuming devhost lock ...")
        fcntl.flock(self.lockfile, fcntl.LOCK_EX)

        if hydra_eval:
            print("Converting hydra eval to channel and image urls")
            # Compatibility layer: convert the hydra eval to image_url and
            # channel_url
            if image_url or channel_url:
                raise ValueError(
                    "Either `hydra_eval` or both of `image_url` and `channel_url` must be given - not both."
                )

            response = requests.get(
                f"https://hydra.flyingcircus.io/eval/{hydra_eval}/job/release",
                headers={"Accept": "application/json"},
            )
            response.raise_for_status()
            build_id = response.json()["id"]
            channel_url = f"https://hydra.flyingcircus.io/build/{build_id}/download/1/nixexprs.tar.xz"
            print(f"\tchannel_url={channel_url}")
            response = requests.get(
                f"https://hydra.flyingcircus.io/eval/{hydra_eval}/job/images.dev-vm",
                headers={"Accept": "application/json"},
            )
            response.raise_for_status()
            for id, product in response.json()["buildproducts"].items():
                if product["subtype"] == "img":
                    image_url = f"https://hydra.flyingcircus.io/build/{response.json()['id']}/download/{id}"
                    break
            else:
                raise RuntimeError(
                    f"Could not find URL for base image for hydra eval {hydra_eval}."
                )
            print(f"\timage_url={image_url}")
        del hydra_eval

        if not channel_url:
            raise ValueError("Missing `channel_url` parameter.")
        if not image_url:
            raise ValueError("Missing `image_url` parameter.")

        if os.path.isfile(self.config_file):
            self.cfg = json.load(open(self.config_file))

        self.cfg["online"] = True
        self.cfg["cpu"] = cpu
        self.cfg["name"] = self.name
        self.cfg["memory"] = memory
        self.cfg["aliases"] = aliases
        self.cfg["location"] = location
        self.cfg["disk_size"] = disk_size
        self.cfg["image_url"] = image_url
        self.cfg["channel_url"] = image_url
        self.cfg["last_deploy_date"] = datetime.datetime.now(
            datetime.UTC
        ).isoformat()

        if "user" not in self.cfg:
            self.cfg["user"] = os.getlogin()
        if "creation-date" not in self.cfg:
            self.cfg["creation-date"] = datetime.datetime.now(
                datetime.UTC
            ).isoformat()

        if "id" not in self.cfg:
            known_ids = set(vm["id"] for vm in list_all_vm_configs())
            for candidate in range(MAX_VM_ID):
                if candidate not in known_ids:
                    self.cfg["id"] = candidate
                    break
            else:
                raise RuntimeError("Could not find free VM ID.")

        # The MAC address is calculated every time deterministically
        srv_mac = f"0203{self.cfg['id']:08x}"
        self.cfg["srv-mac"] = ":".join(
            srv_mac[i : i + 2] for i in range(0, 12, 2)
        )

        if "srv-ip" not in self.cfg:
            known_ips = set(
                ipaddress.ip_address(vm["srv-ip"])
                for vm in list_all_vm_configs()
            )
            known_ips.add(NETWORK.broadcast_address)
            known_ips.add(NETWORK.network_address)
            known_ips.add(NETWORK[1])  # gateway
            for candidate in NETWORK:
                if candidate not in known_ips:
                    self.cfg["srv-ip"] = candidate.exploded
                    break
            else:
                raise RuntimeError("Could not find free SRV IP address.")

        vm_nix_file_existed = os.path.isfile(self.nix_file)

        try:
            with open(self.config_file, mode="w") as f:
                f.write(json.dumps(self.cfg))

            write_nix_file(self.nix_file, self.cfg)

            self.data_dir.mkdir(parents=True, exist_ok=True)
            VM_BASE_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
            vm_has_image = os.path.isfile(self.image_file)

            if not vm_has_image:
                image_url_hash = hashlib.sha256(
                    image_url.encode("utf-8")
                ).hexdigest()
                vm_base_image_path = (
                    VM_BASE_IMAGE_DIR / f"{image_url_hash}.qcow2"
                )
                if not os.path.isfile(vm_base_image_path):
                    print(
                        f"Downloading base image from {image_url} to {vm_base_image_path}"
                    )
                    vm_base_image_path_tmp = (
                        VM_BASE_IMAGE_DIR / f"{image_url_hash}.qcow2.tmp"
                    )
                    # Download the base image. We rename the file afterwards
                    # to ensure that the image is fully there.
                    r = requests.get(image_url)
                    r.raise_for_status()
                    with open(vm_base_image_path_tmp, "wb") as f:
                        f.write(r.content)
                    os.rename(vm_base_image_path_tmp, vm_base_image_path)
                print("Creating VM image ...")
                run(
                    "cp",
                    "--reflink=auto",
                    vm_base_image_path,
                    self.image_file_tmp,
                )
                # Update cache freshness, avoid this base image being deleted
                # in the next 3 months.
                vm_base_image_path.touch()

                print("Preparing VM image for first boot ...")
                with tempfile.TemporaryDirectory() as image_mount_directory:
                    # the 10 is the number of max. nbd devices provided by the kernel
                    nbd_number = None
                    for i in range(8):
                        if check_if_nbd_device_is_used(i):
                            nbd_number = i
                            break
                    if nbd_number is None:
                        raise RuntimeError("There is no unused nbd device.")
                    try:
                        run(
                            "qemu-nbd",
                            f"--connect=/dev/nbd{nbd_number}",
                            self.image_file_tmp,
                        )
                        while True:
                            if check_if_nbd_device_is_used(nbd_number):
                                time.sleep(0.5)
                                break

                        # xfs_admin gets confused by conflicting fs labels, see PL-133416
                        # So use xfs_db directly
                        run(
                            # XXX: keep in sync with the args from the `xfs_admin`
                            # shell script
                            "xfs_db",
                            "-x",
                            "-c",
                            "uuid generate",
                            f"/dev/nbd{nbd_number}p1",
                        )

                        run(
                            "mount",
                            f"/dev/nbd{nbd_number}p1",
                            image_mount_directory,
                        )

                        enc_file = (
                            Path(image_mount_directory) / "etc/nixos/enc.json"
                        )
                        enc = generate_enc(self.cfg)
                        enc["parameters"]["environment_url"] = channel_url
                        enc_file.write_text(json.dumps(enc), encoding="utf-8")
                    finally:
                        # even for partially successful operations (e.g. successful
                        # nbd map, but failing mount) try to clean everything up
                        errs = []
                        try:
                            run("umount", image_mount_directory)
                        except Exception as e:
                            errs.append(e)
                        try:
                            run(
                                "qemu-nbd",
                                "--disconnect",
                                f"/dev/nbd{nbd_number}",
                            )
                        except Exception as e:
                            errs.append(e)

                        if errs:
                            print(
                                "Suppressed the following exceptions during cleanup:",
                                errs,
                            )
                os.rename(self.image_file_tmp, self.image_file)

            # Make sure the VM is now online, even if was previously offline
            run("fc-manage", "switch")

            fcntl.flock(self.lockfile, fcntl.LOCK_UN)
            # Wait for the VM to get online
            print("Waiting for VM to become pingable ...")
            ping_timeout = TimeOut(120)
            while ping_timeout.tick():
                response = os.system(f"ping -c 1 {self.cfg['srv-ip']}")
                if response == 0:
                    break
                else:
                    time.sleep(0.5)
            else:
                raise RuntimeError("VM did not become pingable in time.")

            # wait for port 22 to accept connections
            print("Waiting for SSH to become available ...")
            ssh_timeout = TimeOut(60)
            while ssh_timeout.tick():
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(5)
                result = sock.connect_ex((self.cfg["srv-ip"], 22))
                sock.close()
                if result == 0:
                    break
                else:
                    time.sleep(0.5)
            else:
                raise RuntimeError("SSH did not become available in time.")

            # Check if disk resize is needed by querying current disk size via QMP
            block_info = self.qmp.command("query-block")
            current_size = None
            for device in block_info:
                if device.get("device") == "root":
                    current_size = (
                        device.get("inserted", {})
                        .get("image", {})
                        .get("virtual-size")
                    )
                    break

            if current_size is not None and self.cfg.get("disk_size"):
                new_size_bytes = parse_disk_size(self.cfg["disk_size"])
                if new_size_bytes < current_size:
                    raise ValueError(
                        f"Cannot downsize VM disk from {current_size} bytes to {self.cfg['disk_size']}. "
                        "XFS filesystem does not support shrinking. "
                        "Only disk expansion (upsizing) is supported."
                    )
                elif new_size_bytes > current_size:
                    print(
                        f"Disk size changed from {current_size} bytes to {self.cfg['disk_size']}, resizing..."
                    )
                    self.qmp.command(
                        "block_resize", device="root", size=new_size_bytes
                    )
                    # now, ssh into the VM and resize the filesystem using sudo fc-resize-disk
                    run(
                        "ssh",
                        "-o",
                        "StrictHostKeyChecking=no",
                        "-i",
                        "/var/lib/devhost/ssh_bootstrap_key",
                        f"developer@{self.name}",
                        "sudo fc-resize-disk",
                    )
                    print("Disk resize completed successfully.")
                else:
                    print(
                        f"Disk size already at {self.cfg['disk_size']}, no resize needed."
                    )
            else:
                print(
                    f"No disk size specified or current size unknown: current_size={current_size} self.cfg.get('disk_size')={self.cfg.get('disk_size')}"
                )

            if vm_has_image:
                print("Syncing VM enc data into running VM ...")
                # We need to support a deviating channel as the developer might be using
                # a checkout or version of fc-nixos that isn't available from a URL
                # for bootstrapping.
                with tempfile.TemporaryDirectory() as tmpdir:
                    enc_file = Path(tmpdir) / "enc.json"
                    run(
                        "rsync",
                        "-e",
                        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /var/lib/devhost/ssh_bootstrap_key",
                        "--rsync-path=sudo rsync",
                        f"developer@{self.name}:/etc/nixos/enc.json",
                        str(enc_file),
                    )
                    enc = json.loads(enc_file.read_text(encoding="utf-8"))
                    enc = merge_dicts(enc, generate_enc(self.cfg))
                    if update_channel:
                        enc["parameters"]["environment_url"] = channel_url
                    enc_file.write_text(json.dumps(enc), encoding="utf-8")
                    run(
                        "rsync",
                        "-e",
                        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /var/lib/devhost/ssh_bootstrap_key",
                        "--rsync-path=sudo rsync",
                        str(enc_file),
                        f"developer@{self.name}:/etc/nixos/enc.json",
                    )

        except Exception as e:
            # We want the script to end in a state, where other VMs can be
            # started without a problem. So mainly, if the VM is started for
            # the first time, we just destroy it. If a VM is new, is
            # determined by the existence of their nix file, as it controls
            # the associated systemd unit.
            if not vm_nix_file_existed:
                self.destroy()
            raise e

    def list_vms(self, long_format, user=None, location=None):
        vms = list_all_vm_configs()
        if user is not None:
            vms = filter(lambda x: x.get("user") == user, vms)
        if long_format:
            vms_output = [
                [
                    vm["name"],
                    vm.get("online", "---"),
                    vm.get("user", "---"),
                    vm.get("creation-date", "---"),
                    vm.get("last_deploy_date", "---"),
                ]
                for vm in vms
            ]
            print(
                tabulate(
                    vms_output,
                    headers=[
                        "name",
                        "online",
                        "user",
                        "creation date",
                        "last deploy date",
                    ],
                )
            )
        else:
            for vm in vms:
                print(vm["name"])

    def cleanup(self, shutdown_days, delete_days, location=None):
        fcntl.flock(self.lockfile, fcntl.LOCK_EX)

        print("Cleaning up the devhost now.")
        vm_shut_down = False
        for vm_cfg in list_all_vm_configs():
            if "last_deploy_date" not in vm_cfg:
                vm_cfg["last_deploy_date"] = datetime.datetime.now(
                    datetime.UTC
                ).isoformat()
                with open(CONFIG_DIR / f"{vm_cfg['name']}.json", mode="w") as f:
                    f.write(json.dumps(vm_cfg))

            # existing VMs might have persisted a timezone-naive timestamp
            last_deploy_date_parsed = datetime.datetime.fromisoformat(
                vm_cfg["last_deploy_date"]
            ).astimezone(datetime.UTC)
            if last_deploy_date_parsed < (
                datetime.datetime.now(datetime.UTC)
                - datetime.timedelta(days=delete_days)
            ):
                print(f"Deleting VM {vm_cfg['name']}.")
                Manager(name=vm_cfg["name"]).destroy()

            elif last_deploy_date_parsed < (
                datetime.datetime.now(datetime.UTC)
                - datetime.timedelta(days=shutdown_days)
            ):
                if not vm_cfg["online"]:
                    continue
                print(f"Shutting down VM {vm_cfg['name']}.")
                vm_shut_down = True
                vm_cfg["online"] = False
                write_nix_file(CONFIG_DIR / f"{vm_cfg['name']}.nix", vm_cfg)
                with open(CONFIG_DIR / f"{vm_cfg['name']}.json", mode="w") as f:
                    f.write(json.dumps(vm_cfg))

        if vm_shut_down:
            run("fc-manage", "switch")

        print("Cleaning up old VM base images now.")
        VM_BASE_IMAGE_DIR.mkdir(parents=True, exist_ok=True)
        for stored_image in VM_BASE_IMAGE_DIR.glob("*"):
            age = time.time() - stored_image.stat().st_mtime
            if age < 3 * MONTH:
                continue
            stored_image.unlink()

    def login(self, location=None):
        os.execvp(
            "ssh",
            [
                "ssh",
                "-i",
                "/var/lib/devhost/ssh_bootstrap_key",
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-l",
                "developer",
                self.name,
            ],
        )

    def proc(self):
        """Qemu processes as psutil.Process object.

        Returns None if the PID file does not exist or the process is
        not running.
        """
        try:
            with self.pid_file.open() as p:
                # pid file may contain trailing lines with garbage
                for line in p:
                    proc = psutil.Process(int(line))
                    marker = f" -name {self.name} "
                    # Do not use proc.name() here - it's only 16 bytes ...
                    if marker not in " ".join(proc.cmdline()):
                        break
                    return proc
        except (IOError, OSError, ValueError, psutil.NoSuchProcess):
            pass

    def process_exists(self):
        proc = self.proc()
        if proc is None:
            return False
        return proc.is_running()

    def is_running(self):
        # Simplified version from fc.qemu

        # This method must be very reliable. It is perfectly OK to error
        # out in the case of inconsistencies. But a "true" must mean:
        # we have a working Qemu instance here. And a "false" must mean:
        # there is no reason to think that any remainder of a Qemu process is
        # still running

        timeout = TimeOut(10, raise_on_timeout=False)
        while timeout.tick():
            # Try to find a stable result within a few seconds - ignore
            # unstable results in between. Qemu might just be starting
            # and the process already there but QMP not, or vice versa.

            # a) is there a process?
            expected_process_exists = self.process_exists()

            # b) is the monitor port around reliably? Let's assume it does.
            qmp_available = self.qmp

            # c) is the monitor available and talks to us?
            monitor_says_running = False
            status = {}

            if qmp_available:
                try:
                    status = self.qmp.command("query-status")
                except (QMPConnectError, socket.error):
                    # Force a reconnect in the next iteration.
                    self.__qmp.close()
                    self.__qmp = None
                    qmp_available = False
                    monitor_says_running = False
                else:
                    monitor_says_running = status["running"]

            if (
                expected_process_exists
                and qmp_available
                and monitor_says_running
            ):
                return True

            if not expected_process_exists and not qmp_available:
                return False

        # The timeout passed and we were not able to determine a consistent
        # result. :/
        raise RuntimeError(
            "Can not determine whether Qemu is running. "
            "Process exists: {}, QMP socket reliable: {}, "
            "Status is running: {}".format(
                expected_process_exists, qmp_available, monitor_says_running
            ),
            status,
        )

    def graceful_shutdown(self):
        if not self.qmp:
            return
        self.qmp.command("system_powerdown")

    def shutdown(self, location=None):
        timeout = TimeOut(30, interval=5)
        try:
            self.graceful_shutdown()
        except (socket.error, RuntimeError):
            pass
        while timeout.tick():
            print(f"checking-offline, remaining={timeout.remaining}")
            if not self.is_running():
                print("vm-offline")
                print("graceful-shutdown-completed")
                break
        else:
            # Shutdown failed, now the VM gets killed by systemd
            print("graceful-shutdown-failed")
