#! /usr/bin/env python3
import os
import sys
from pathlib import Path
from socket import gethostname
from subprocess import run

CEPH_DIR = Path("/ceph/")
DISK_SIZE = 4 * 1024**3
ACTIONS = ["create", "destroy"]


def create_cluster():
    CEPH_DIR.mkdir(exist_ok=True)
    disk_journal = CEPH_DIR / "disk-journal"
    disk_osd = CEPH_DIR / "disk-osd"
    with (
        open(disk_journal, "wb") as journal,
        open(disk_osd, "wb") as osd,
    ):
        journal.seek(DISK_SIZE)
        journal.truncate()
        osd.seek(DISK_SIZE)
        osd.truncate()
    loopdev_journal = run(
        ["losetup", "-f", "--show", str(disk_journal)],
        check=True,
        capture_output=True,
        encoding="utf-8",
    ).stdout.strip()
    loopdev_osd = run(
        ["losetup", "-f", "--show", str(disk_osd)],
        check=True,
        capture_output=True,
        encoding="utf-8",
    ).stdout.strip()
    run(["fc-ceph", "osd", "prepare-journal", loopdev_journal], check=True)
    run(
        [
            "fc-ceph",
            "mon",
            "create",
            "--no-encrypt",
            "--size", "500m",
            "--bootstrap-cluster",
        ],
        check=True,
    )  # fmt: skip

    # fix default warnings by enabling new backwards-incompatible client auth behaviour
    run(
        [
            "ceph",
            "config",
            "set",
            "mon",
            "auth_allow_insecure_global_id_reclaim",
            "false",
        ],
        check=True,
    )
    run(["ceph", "mon", "enable-msgr2"], check=True)

    # required for mgr bootstrap
    run(
        [
            "fc-ceph",
            "keys",
            "mon-update-single-client",
            "host1",
            "ceph_osd,ceph_mon,ceph_rgw",
            "salt-for-host1-dhkasjy9",
        ]
    )

    run(
        [
            "fc-ceph",
            "mgr",
            "create",
            "--no-encrypt",
            "--size", "500m",
        ],
        check=True,
    )  # fmt: skip

    run(
        [
            "fc-ceph",
            "osd",
            "create-bluestore",
            "--no-encrypt",
            "--wal=internal",
            loopdev_osd
        ],
        check=True,
    )  # fmt: skip

    run(
        ["ceph", "osd", "crush", "move", gethostname(), "root=default"],
        check=True,
    )

    # create rbd pools and some test images
    # rbd pool is not created by default anymore
    run(
        ["ceph", "osd", "pool", "create", "rbd", "64", "--size", "1"],
        check=True,
    )
    run(["rbd", "pool", "init"], check=True)
    for img in ("test1", "test2"):
        run(["rbd", "create", "--size=20M", img])

    # for now, it is a single-host cluster
    for poolname in ("device_health_metrics", "rbd"):
        run(
            [
                "ceph",
                "osd",
                "pool",
                "set",
                poolname,
                "size",
                "1",
                "--yes-i-really-mean-it",
            ]
        )
        run(["ceph", "osd", "pool", "set", poolname, "min_size", "1"])
        # XXX: ensure presence of rbd pools and also consider those


def destroy_cluster():
    run(["systemctl", "stop", "fc-ceph-mon"])
    run(["systemctl", "stop", "fc-ceph-mgr"])
    run(["systemctl", "stop", "fc-ceph-osd@0.service"])
    run(["umount", "/srv/ceph/mgr/ceph-host1"])
    run(["umount", "/srv/ceph/mon/ceph-host1"])
    run(["umount", "/srv/ceph/osd/ceph-0"])
    run(["vgremove", "vgjnl00", "-y"])
    run(["vgremove", "vgosd-0", "-y"])
    run(["losetup", "-D"])
    run(["rm", "-rf", CEPH_DIR])


def main(argv):
    if len(argv) < 2 or argv[1] not in ACTIONS:
        print("Invalid actions, avaliable:", ACTIONS)
        sys.exit(1)
    match argv[1]:
        case "create":
            create_cluster()
        case "destroy":
            destroy_cluster()


if __name__ == "__main__":
    main(sys.argv)
