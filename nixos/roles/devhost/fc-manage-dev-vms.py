import argparse
import fcntl
import ipaddress
import json
import os.path
import shutil
import subprocess
import sys
import textwrap
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


class Manager:
    vm: str  # Name of the managed VM

    def __init__(self, vm):
        self.vm = vm
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
                    f"""\
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

            # XXX Leona customizes the VM directly without booting it
            # anonymously
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

    vm = getattr(args, "name", None)
    kwargs = dict(args._get_kwargs())
    del kwargs["func"]
    if "name" in kwargs:
        del kwargs["name"]

    manager = Manager(vm)
    getattr(manager, func)(**kwargs)
