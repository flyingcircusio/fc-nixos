import argparse
import datetime
import fcntl
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

MAX_VM_ID = 1024
NETWORK = ipaddress.ip_network("10.12.0.0/16")
CONFIG_DIR = Path("/etc/devhost/vm-configs")
VM_DATA_DIR = Path("/var/lib/devhost/vms")


def run(*args, **kwargs):
    kwargs["check"] = True
    return subprocess.run(args, **kwargs)


def list_all_vm_configs():
    for vm in CONFIG_DIR.glob("*.json"):
        yield json.load(open(vm))


def check_if_nbd_device_is_used(number):
    with open(f"/sys/class/block/nbd{number}/size", "r") as f:
        return f.read() != "0"


def generate_enc_json(cfg, channel_url):
    return json.dumps(
        {
            "name": cfg["name"],
            "parameters": {
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

    def destroy(self, location=None):
        # We want do destroy everything existing for a VM.
        # If something in the provisioning failed, there might not be all files.
        if os.path.isfile(self.config_file):
            self.config_file.unlink()
        if os.path.isfile(self.nix_file):
            self.nix_file.unlink()
        shutil.rmtree(self.data_dir, ignore_errors=True)
        run("fc-manage", "-v", "-b")

    def ensure(self, cpu, memory, hydra_eval, aliases, location):
        # Nixify the alias list
        response = requests.get(
            f"https://hydra.flyingcircus.io/eval/{hydra_eval}/job/release",
            headers={"Accept": "application/json"},
        )
        response.raise_for_status()
        build_id = response.json()["id"]
        channel_url = f"https://hydra.flyingcircus.io/build/{build_id}/download/1/nixexprs.tar.xz"

        if os.path.isfile(self.config_file):
            self.cfg = json.load(open(self.config_file))

        self.cfg["cpu"] = cpu
        self.cfg["name"] = self.name
        self.cfg["memory"] = memory
        self.cfg["hydra_eval"] = hydra_eval
        self.cfg["aliases"] = aliases
        self.cfg["location"] = location

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

            nix_aliases = " ".join(map(lambda x: f'"{x}"', self.cfg["aliases"]))
            with open(self.nix_file, mode="w") as f:
                f.write(
                    textwrap.dedent(
                        f"""\
                # DO NOT TOUCH!
                # Managed by fc-manage-dev-vms
                {{ ... }}: {{
                  flyingcircus.roles.devhost.virtualMachines = {{
                    "{self.cfg['name']}" = {{
                      id = {self.cfg['id']};
                      memory = "{self.cfg['memory']}";
                      cpu = {self.cfg['cpu']};
                      srvIp = "{self.cfg['srv-ip']}";
                      srvMac = "{self.cfg['srv-mac']}";
                      aliases = [ {nix_aliases} ];
                    }};
                  }};
                }}
                """
                    )
                )

            os.makedirs(self.data_dir, exist_ok=True)

            if not os.path.isfile(self.image_file):
                response = requests.get(
                    f"https://hydra.flyingcircus.io/eval/{hydra_eval}/job/images.dev-vm",
                    headers={"Accept": "application/json"},
                )
                response.raise_for_status()

                vm_base_image_store_path: str
                for product in response.json()["buildproducts"].values():
                    if product["subtype"] == "img":
                        vm_base_image_store_path = product["path"]
                        break
                else:
                    raise RuntimeError(
                        "Could not find store path for base image"
                    )
                run("nix-store", "-r", vm_base_image_store_path)
                # Reflinks would be nice here: to reduce startup time and to
                # reduce amount of space needed. However, the store mount
                # doesn't allow us to :(
                shutil.copyfile(vm_base_image_store_path, self.image_file_tmp)

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
                        run("qemu-nbd", "--disconnect", f"/dev/nbd{nbd_number}")
                os.rename(self.image_file_tmp, self.image_file)
            else:
                with tempfile.NamedTemporaryFile(mode="w") as f:
                    f.write(generate_enc_json(self.cfg, channel_url))
                    f.flush()
                    run(
                        "rsync",
                        "-e",
                        "ssh -o StrictHostKeyChecking=no -i /var/lib/devhost/ssh_bootstrap_key",
                        "--rsync-path=sudo rsync",
                        f.name,
                        f"developer@{self.name}:/etc/nixos/enc.json",
                    )

            run("fc-manage", "-v", "-b")

            # We need to wait for the VM to get online
            while True:
                response = os.system(f"ping -c 1 {self.cfg['srv-ip']}")
                if response == 0:
                    break
                else:
                    time.sleep(0.5)

        except Exception as e:
            # We want the script to end in a state, where other VMs can be started without a problem.
            # So mainly, if the VM is started for the first time, we just destroy it.
            # If a VM is new, is determined by the existence of their nix file, as it controls the
            # associated systemd unit.
            if not vm_nix_file_existed:
                self.destroy()
            raise e


def main():
    a = argparse.ArgumentParser(description="Manage DevHost VMs.")
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
    p.add_argument(
        "--hydra-eval", type=int, help="hydra eval to use for base image"
    )
    p.add_argument(
        "--aliases",
        type=space_separated_list,
        default=[],
        help="aliases for the nginx",
    )
    p.add_argument("name", help="name of the VM")
    p.add_argument("--location", help="location the VMs live in")

    p = sub.add_parser("destroy", help="Destroy a given VM.")
    p.set_defaults(func="destroy")
    p.add_argument("name", help="name of the VM")
    p.add_argument("--location", help="location the VMs live in")

    args = a.parse_args()
    func = args.func

    if func == "print_usage":
        a.print_usage()
        sys.exit(1)

    lockfile = open("/run/fc-manage-dev-vms", "a+")
    fcntl.flock(lockfile, fcntl.LOCK_EX)

    os.makedirs(CONFIG_DIR, exist_ok=True)

    name = getattr(args, "name", None)
    kwargs = dict(args._get_kwargs())
    del kwargs["func"]
    if "name" in kwargs:
        del kwargs["name"]

    manager = Manager(name)
    getattr(manager, func)(**kwargs)


if __name__ == "__main__":
    main()
