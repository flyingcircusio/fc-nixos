import argparse
import os
import socket
import subprocess
import time

import yaml

IMAGE_POOL = "rbd.hdd"


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
        snapshots = cmd(
            'rbd --id "{ceph_id}" snap ls {image_pool}/{image}'.format(
                image=image, image_pool=IMAGE_POOL, ceph_id=self.disk.ceph_id
            )
        )
        snapshot = snapshots[-1].split()
        try:
            int(snapshot[0])
        except ValueError:
            raise RuntimeError(
                "Could not find a valid snapshot for image {}.".format(image)
            )
        snapshot = snapshot[1]
        cmd(
            'rbd --id "{ceph_id}" clone {image_pool}/{image}@{snapshot} '
            "{pool}/{name}.root".format(
                image_pool=IMAGE_POOL,
                image=image,
                snapshot=snapshot,
                pool=self.enc["parameters"]["rbd_pool"],
                name=self.name,
                ceph_id=self.disk.ceph_id,
            )
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
    os.environ["LC_ALL"] = os.environ["LANG"] = "en_US.utf-8"

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
    node = Node(args.name, Disk)
    node.identify()
    node.setup()
    title("Finished")
