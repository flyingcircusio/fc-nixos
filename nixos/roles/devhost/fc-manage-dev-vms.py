#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3Packages.requests xfsprogs qemu

import argparse
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
        yield json.read(open(vm))


def check_if_nbd_device_is_used(number):
    with open(f"/sys/class/block/nbd{number}/size", "r") as f:
        return f.read() != "0"


def generate_enc_json(cfg):
    return json.dumps(
        {
            "name": cfg["name"],
            "parameters": {
                "environment_url": cfg["channel_url"],  # todo
                "environment": "dev-vm",
                "interfaces": {
                    "srv": {
                        "bridged": False,
                        "gateways": {
                            "10.12.0.0/20": "10.12.0.1",
                        },
                        # TODO: Set correct MAC
                        "mac": "todo",
                        "networks": {
                            "10.12.0.0/20": [cfg["srv_ip"]],
                        },
                    }
                },
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

    def destroy(self):
        self.config_file.unlink()
        shutil.rmtree(self.data_dir)
        run("fc-manage", "-v", "-b")

    def ensure(self, cpu, memory, hydra_eval, aliases):
        # Nixify the alias list
        aliases = " ".join(f'"{a}"' for a in aliases)
        response = requests.get(
            "https://hydra.flyingcircus.io/eval/{hydra_eval}/job/release",
            headers={"Accept", "application/json"},
        )
        response.raise_for_status()
        build_id = response.json()["id"]
        channel_url = f"https://hydra.flyingcircus.io/build/{build_id}/download/1/nixexprs.tar.xz"

        # Be opportunistic here
        os.makedirs(self.config_file.parent)

        if self.config_file.exists:
            self.cfg = cfg = json.load(open(self.config_file))

        cfg["cpu"] = cpu
        cfg["name"] = name
        cfg["memory"] = memory
        cfg["hydra_eval"] = hydra_eval
        cfg["aliases"] = aliases

        if "id" not in cfg:
            known_ids = set(vm["id"] for vm in list_all_vm_configs())
            for candidate in range(1024):
                if candidate not in known_ids:
                    cfg["id"] = candidate
                    break
            else:
                raise RuntimeError("Could not find free VM ID.")

        if "srv-ip" not in self.cfg:
            known_ips = set(
                ipaddress.ip_address(vm["srv-ip"])
                for vm in list_all_vm_configs()
            )
            known_ips.add(NETWORK.broadcast_address)
            known_ips.add(NETWORK.network_address)
            for candidate in NETWORK:
                if candidate not in known_ids:
                    cfg["srv-ip"] = candidate
                    break
            else:
                raise RuntimeError("Could not find free SRV IP address.")

        with open(self.nix_file) as f:
            f.write(
                textwrap.dedent(
                    # TODO: f
                    """\
            # DO NOT TOUCH!
            # Managed by fc-manage-dev-vms
            { ... }: {
              flyingcircus.roles.devhost.virtualMachines = {
                "{cfg['name']}" = {
                  memory = "{cfg['memory']}";
                  cores = "{cfg['cores']};
                  srv_ip = "{cfg['srv-ip']};
                  id = "{cfg['id']};
                };
              };
            }
            """
                )
            )

        os.makedirs(self.data_dir)

        if not self.image_file.exists:
            response = requests.get(
                f"https://hydra.flyingcircus.io/eval/{hydra_eval}/job/images.dev-vm",
                headers={"Accept": "application/json"},
            )
            response.raise_for_status()

            vm_base_image_storage_path: str
            for product in response.json()["buildproducts"]:
                if product["subtype"] == "img":
                    vm_base_image_storage_path = product["path"]
                    break
            else:
                raise RuntimeError("Could not find store path for base image")
            run("nix-store", "-r", vm_base_image_store_path)
            # Reflinks would be nice here: to reduce startup time and to
            # reduce amount of space needed. However, the store mount
            # doesn't allow us to :(
            shutil.copyfile(vm_base_image_store_path, self.image_file_tmp)

            image_mount_directory = tempfile.TemporaryDirectory()
            # the 10 is the number of max. nbd devices provided by the kernel
            nbd_number = None
            for i in range(10):
                if check_if_nbd_device_is_used(i):
                    nbd_number = i
                    break
            if nbd_number is None:
                raise RuntimeError("There is no unused nbd device.")

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
            run("xfs_admin", "-U", new_fs_uuid, f"/dev/nbd{nbd_number}p1")

            run("mount", f"/dev/nbd{nbd_number}p1", iamge_mount_directory.name)

            with open(image_mount_directory / "etc/nixos/enc.json", "w") as f:
                f.write(generate_enc_json(cfg))

            run("umount", image_mount_directory.name)
            run("qemu-nbd", "--disconnect", f"/dev/nbd{nbd_number}")
            os.rename(self.image_file_tmp, self.image_file)
        else:
            # XXX we still need to ssh here, but we can leverage the enc
            # generation code from above
            # jq -n --arg channel_url "$channel_url" '{parameters: {environment_url: $channel_url, environment: "dev-vm"}}' > /tmp/devhost-vm-enc.json
            # rsync -e "ssh -o StrictHostKeyChecking=no -i /var/lib/devhost/ssh_bootstrap_key" --rsync-path="sudo rsync" /tmp/devhost-vm-enc.json developer@$vm:/etc/nixos/enc.json
            pass

        run("fc-manage", "-v", "-b")


def main():
    a = argparse.ArgumentParser(description="Manage DevHost VMs.")
    a.set_defaults(func="print_usage")
    sub = a.add_subparsers(title="subcommands")

    def space_separated_list(str):
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
        default="",
        help="hydra eval to use for base image",
    )
    p.add_argument("name", help="name of the VM")

    p = sub.add_parser("destroy", help="Destroy a given VM.")
    p.add_argument("name", help="name of the VM")

    args = a.parse_args()
    func = args.func

    if func == "print_usage":
        a.print_usage()
        sys.exit(1)

    lockfile = open("/run/fc-manage-dev-vms", "a+")
    fcntl.flock(lockfile, fcntl.LOCK_EX)

    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR)

    name = getattr(args, "name", None)
    kwargs = dict(args._get_kwargs())
    del kwargs["func"]
    if "name" in kwargs:
        del kwargs["name"]

    manager = Manager(name)
    getattr(manager, func)(**kwargs)
