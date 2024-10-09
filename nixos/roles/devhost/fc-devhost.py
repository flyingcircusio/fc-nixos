import argparse
import datetime
import fcntl
import hashlib
import ipaddress
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import uuid
from pathlib import Path

import requests
from tabulate import tabulate

MAX_VM_ID = 1024
NETWORK = ipaddress.ip_network("10.12.0.0/16")
CONFIG_DIR = Path("/etc/devhost/vm-configs")
VM_BASE_IMAGE_DIR = Path("/var/lib/devhost/base-images")
VM_DATA_DIR = Path("/var/lib/devhost/vms")
LOCKFILE_PATH = "/run/fc-devhost-vm"

MONTH = 60 * 60 * 24 * 30


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
            "{cfg['name']}" = {{
              enable = {"true" if cfg['online'] else "false"};
              id = {cfg['id']};
              memory = "{cfg['memory']}";
              cpu = {cfg['cpu']};
              srvIp = "{cfg['srv-ip']}";
              srvMac = "{cfg['srv-mac']}";
              aliases = [ {nix_aliases} ];
            }};
          }};
        }}
        """
            )
        )


def generate_enc_json(cfg, channel_url):
    return json.dumps(
        {
            "name": cfg["name"],
            "parameters": {
                "cores": cfg["cpu"],
                "environment_url": channel_url,
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
    )


class Manager:
    name: str  # Name of the managed VM

    def __init__(self, name):
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
    def lockfile(self):
        return open(LOCKFILE_PATH, "a+")

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
        run("fc-manage", "-v", "-b")

    def ensure(
        self,
        cpu,
        memory,
        aliases,
        location,
        hydra_eval=None,
        image_url=None,
        channel_url=None,
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
        self.cfg["image_url"] = image_url
        self.cfg["channel_url"] = image_url
        self.cfg["last_deploy_date"] = datetime.datetime.utcnow().isoformat()

        if "user" not in self.cfg:
            self.cfg["user"] = os.getlogin()
        if "creation-date" not in self.cfg:
            self.cfg["creation-date"] = datetime.datetime.utcnow().isoformat()

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

            self.data_dir.mkdir(exist_ok=True)
            VM_BASE_IMAGE_DIR.mkdir(exist_ok=True)
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

                        new_fs_uuid = str(uuid.uuid4())
                        run(
                            "xfs_admin",
                            "-U",
                            new_fs_uuid,
                            f"/dev/nbd{nbd_number}p1",
                        )

                        run(
                            "mount",
                            f"/dev/nbd{nbd_number}p1",
                            image_mount_directory,
                        )

                        enc_file_path = (
                            Path(image_mount_directory) / "etc/nixos/enc.json"
                        )
                        with open(enc_file_path, mode="w") as f:
                            f.write(generate_enc_json(self.cfg, channel_url))
                    finally:
                        run("umount", image_mount_directory)
                        run(
                            "qemu-nbd", "--disconnect", f"/dev/nbd{nbd_number}"
                        )
                os.rename(self.image_file_tmp, self.image_file)

            # Make sure the VM is now online, even if was previously offline
            run("fc-manage", "-v", "-b")

            fcntl.flock(self.lockfile, fcntl.LOCK_UN)
            # Wait for the VM to get online
            print("Waiting for VM to become pingable ...")
            while True:
                response = os.system(f"ping -c 1 {self.cfg['srv-ip']}")
                if response == 0:
                    break
                else:
                    time.sleep(0.5)

            if vm_has_image:
                print("Syncing VM enc data into running VM ...")
                with tempfile.NamedTemporaryFile(mode="w") as f:
                    f.write(generate_enc_json(self.cfg, channel_url))
                    f.flush()
                    run(
                        "rsync",
                        "-e",
                        "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /var/lib/devhost/ssh_bootstrap_key",
                        "--rsync-path=sudo rsync",
                        f.name,
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
                    vm.get("user", "---"),
                    vm.get("creation-date", "---"),
                    vm["name"],
                ]
                for vm in vms
            ]
            print(
                tabulate(vms_output, headers=["user", "creation date", "name"])
            )
        else:
            for vm in vms:
                print(vm["name"])

    def cleanup(self, location=None):
        fcntl.flock(self.lockfile, fcntl.LOCK_EX)

        print("Cleaning up the devhost now.")
        vm_shut_down = False
        for vm_cfg in list_all_vm_configs():
            if "last_deploy_date" not in vm_cfg:
                vm_cfg["last_deploy_date"] = (
                    datetime.datetime.utcnow().isoformat()
                )
                with open(
                    CONFIG_DIR / f"{vm_cfg['name']}.json", mode="w"
                ) as f:
                    f.write(json.dumps(vm_cfg))

            if datetime.datetime.fromisoformat(vm_cfg["last_deploy_date"]) < (
                datetime.datetime.utcnow() - datetime.timedelta(days=14)
            ):
                print(f"Shutting down VM {vm_cfg['name']}.")
                vm_shut_down = True
                vm_cfg["online"] = False
                write_nix_file(CONFIG_DIR / f"{vm_cfg['name']}.nix", vm_cfg)
                with open(
                    CONFIG_DIR / f"{vm_cfg['name']}.json", mode="w"
                ) as f:
                    f.write(json.dumps(vm_cfg))

            if datetime.datetime.fromisoformat(vm_cfg["last_deploy_date"]) < (
                datetime.datetime.utcnow() - datetime.timedelta(days=31)
            ):
                print(f"Deleting VM {vm_cfg['name']}.")
                Manager(name=vm_cfg["name"]).destroy()

        if vm_shut_down:
            run("fc-manage", "-v", "-b")

        print("Cleaning up old VM base images now.")
        VM_BASE_IMAGE_DIR.mkdir(exist_ok=True)
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


def main():
    a = argparse.ArgumentParser(
        prog="fc-devhost", description="Manage DevHost VMs."
    )
    a.set_defaults(func="print_usage")
    sub = a.add_subparsers(title="subcommands")

    def space_separated_list(str):
        if str == "":
            return []
        return str.split(" ")

    p = sub.add_parser("ensure", help="Create or update a given VM.")
    p.set_defaults(func="ensure")
    p.add_argument("--cpu", type=int, help="number of cores")
    p.add_argument("--memory", type=int, help="amount of memory")
    p.add_argument("--location", help="location the VMs live in")
    p.add_argument("--image-url", type=str, help="url to an image for the vm")
    p.add_argument(
        "--channel-url", type=str, help="url to the nix channel for the vm"
    )
    p.add_argument(
        "--hydra-eval",
        type=int,
        help="hydra eval to use for base image (deprecated, use --image-url and --channel-url)",
    )
    p.add_argument(
        "--aliases",
        type=space_separated_list,
        default=[],
        help="aliases for the nginx",
    )
    p.add_argument("name", help="name of the VM")

    # ---------------------------------

    p = sub.add_parser("destroy", aliases=["rm"], help="Destroy provided VMs.")
    p.set_defaults(func="destroy")
    p.add_argument(
        "name",
        nargs="+",
        help="name(s) of the VMs to be destroyed",
    )
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "list",
        aliases=["ls"],
        help="List VMs. By default all, can be limited by parameters.",
    )
    p.set_defaults(func="list_vms")
    p.add_argument("--user", type=str, help="user name creating the vm")
    p.add_argument(
        "-l",
        "--long-format",
        action="store_true",
        help="show more details of the vms",
    )
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "cleanup",
        help="Cleanup. This is an automated task. In this process old base images will be deleted.",
    )
    p.set_defaults(func="cleanup")
    p.add_argument("--location", help="location the VMs live in")

    # ---------------------------------

    p = sub.add_parser(
        "login",
        help="Login into the specified VM.",
    )
    p.set_defaults(func="login")
    p.add_argument("name", help="name of the VM")
    p.add_argument("--location", help="location the VMs live in")

    args = a.parse_args()
    func = args.func

    if func == "print_usage":
        a.print_usage()
        sys.exit(1)

    CONFIG_DIR.mkdir(exist_ok=True)

    name = getattr(args, "name", None)
    kwargs = dict(args._get_kwargs())

    if func == "destroy":
        for name in args.name:
            manager = Manager(name)
            manager.destroy()

    del kwargs["func"]
    if "name" in kwargs:
        del kwargs["name"]

    manager = Manager(name)
    getattr(manager, func)(**kwargs)


if __name__ == "__main__":
    main()
