import argparse
import os
import socket
import subprocess
import time
from pathlib import Path

import yaml
from fc.util.runners import run

from . import Environment

IMAGE_POOL = "rbd.hdd"
CONFIG_FILE_PATH = Path("/etc/fc-agent.conf")


# This can be replaced later by the new JSON-based runner tooling
def cmd(cmd, filter_empty=True, ignore_error=lambda x: False):
    print(cmd)
    try:
        out = subprocess.check_output(cmd, shell=True)
        out = out.decode("utf-8")
        print((out.strip()))
    except Exception as e:
        if not ignore_error(e):
            print((e.output))
            raise
        out = e.output
    out = out.split("\n")
    out = [_f for _f in out if _f]
    return out


def title(str):
    print()
    print(str)
    print(("-" * len(str)))


class Node(object):

    enc = None
    disk = None
    mountpoint = None

    def __init__(self, name, disk_factory):
        self.disk_factory = disk_factory
        self.name = name

    def identify(self):
        self.enc = yaml.safe_load(open(f"/etc/qemu/vm/{self.name}.cfg"))
        self.disk = self.disk_factory(
            self,
            self.enc["parameters"]["rbd_pool"],
            int(self.enc["parameters"]["disk"]) * 1024,
        )

    def setup(self):
        """Decide which setup mode to use and run it."""
        p = self.enc["parameters"]
        image = p["environment"]

        # use json command output as its output is more stable between Ceph releases
        snapshots = run.json.rbd(
            # fmt: off
            "--id", self.disk.ceph_id,
            "snap", "ls", f"{IMAGE_POOL}/{image}"
            # fmt: on
        )
        print("Snapshots:")
        print("snapid", "name", "size", sep="\t")
        for snap in snapshots:
            print(snap["id"], snap["name"], snap["size"], sep="\t")

        # clone last existing base image snapshot for VM root image
        try:
            last_snap_name = snapshots[-1]["name"]
        except IndexError:
            raise RuntimeError(
                "Could not find a valid snapshot for image {}.".format(image)
            )
        run.rbd(
            # fmt: off
            "--id", self.disk.ceph_id,
            "clone",
            f"{IMAGE_POOL}/{image}@{last_snap_name}",
            f"{self.enc['parameters']['rbd_pool']}/{self.name}.root"
            # fmt: on
        )


class Disk(object):
    def __init__(self, node, pool, size):
        self.node = node
        self.pool = pool
        self.size = size
        self.nodename = self.node.name
        self.ceph_id = socket.gethostname()
        self.rootvol = "{}/{}.root".format(self.pool, self.nodename)
        self.device = "/dev/rbd/{}".format(self.rootvol)
        self.rootpart = "/dev/rbd/{}-part1".format(self.rootvol)

    def partition(self):
        cmd(
            "sgdisk {} -o".format(self.device),
            ignore_error=lambda e: "completed successfully" in e.output,
        )
        cmd(
            "sgdisk {} -a 8192 -n 1:8192:0 -c 1:root -t 1:8300".format(
                self.device
            )
        )
        cmd(
            "sgdisk {} -n 2:2048:+1M -c 2:gptbios -t 2:EF02".format(self.device)
        )

    def apply(self):
        def format(s):
            return s.format(**self.__dict__)

        cmd(format('rbd --id "{ceph_id}" --size {size} create "{rootvol}"'))
        cmd(format('rbd-locktool -l "{rootvol}"'))
        cmd(format('rbd --id "{ceph_id}" map "{rootvol}"'))
        self.partition()
        while not os.path.exists(self.rootpart):
            time.sleep(1)
        cmd(format("mkfs -q -m 1 -t ext4 -L root {rootpart}"))
        cmd(format("tune2fs -e remount-ro {rootpart}"))
        cmd(format('rbd unmap "/dev/rbd/{rootvol}"'))


def main():
    p = argparse.ArgumentParser(description="Create a new VM.")
    p.add_argument(
        "-I",
        "--init",
        action="store_true",
        default=False,
        help="init mode: create-vm gets called from KVM init "
        "script for on-the-fly VM creation; don't use manually!",
    )
    p.add_argument("name", help="name of the virtual machine to create")
    args = p.parse_args()

    title("Establishing system identity")
    # statefully modify execution environment, e.g. PATH and LANG
    environment = Environment(CONFIG_FILE_PATH)
    node = environment.prepare(Node, args.name, Disk)

    node.identify()
    node.setup()
    title("Finished")
