#!/usr/bin/env python3
from os import chdir
from pathlib import Path
from socket import gethostname
from subprocess import DEVNULL, CalledProcessError, run
from sys import exit
from typing import NamedTuple


class UbuntuReleaseMetadata(NamedTuple):
    environment: str
    base: str
    image: str


UBUNTU_RELEASES = [
    UbuntuReleaseMetadata(
        environment="24.04-lts-noble-numbat",
        base="https://cloud-images.ubuntu.com/noble/current",
        image="noble-server-cloudimg-amd64.img",
    )
]


def update_ubuntu_release(release: UbuntuReleaseMetadata) -> int:

    # XXX: in principle this is insecure, because /tmp/ is world-rw and thus the images could be tampered with
    chdir("/tmp/")
    try:
        run(
            "rbd namespace list rbd.hdd | grep -q images-ubuntu",
            shell=True,
            check=True,
            text=True,
            capture_output=True,
        )
    except CalledProcessError:
        print("ERROR: missing namespace `images-ubuntu`")
        return 2

    create_flags: list[str] = []
    if not run(
        ["rbd", "info", f"rbd.hdd/images-ubuntu/{release.environment}"],
        stdout=DEVNULL,
        stderr=DEVNULL,
    ).returncode:
        create_flags.append("-n")

    run(["wget", "-q", f"{release.base}/SHA256SUMS"], check=True)
    checksum = run(
        f"grep {release.image} SHA256SUMS | cut -d ' ' -f 1",
        shell=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    if not run(
        [
            "rbd", "info",
            f"rbd.hdd/images-ubuntu/{release.environment}@rolling-{checksum}",
        ],
        stdout=DEVNULL,
        stderr=DEVNULL,
    ).returncode:  # fmt: skip
        print("OK: image already up to date")
        return 0

    print(f"Detected new checksum: {checksum}")
    Path(release.image).unlink(missing_ok=True)

    print("Downloading new image ...")
    run(["wget", "-q", f"{release.base}/{release.image}"], check=True)
    got_checksum = run(
        f'sha256sum "/tmp/{release.image}" | cut -d " " -f 1',
        shell=True,
        text=True,
        capture_output=True,
    ).stdout.strip()

    if got_checksum != checksum:
        print(
            f"ERROR: download checksum was `{got_checksum}`, expected `{checksum}."
        )
        return 1

    print("Storing new image in Ceph ...")
    run(
        [
            "qemu-img",
            "convert",
            "-p",
            *create_flags,
            release.image,
            f"rbd:rbd.hdd/images-ubuntu/{release.environment}:id={gethostname()}",
        ],
        check=True,
    )
    run(
        [
            "rbd",
            "snap",
            "create",
            f"rbd.hdd/images-ubuntu/{release.environment}@rolling-{checksum}",
        ],
        check=True,
    )
    run(
        [
            "rbd",
            "snap",
            "protect",
            f"rbd.hdd/images-ubuntu/{release.environment}@rolling-{checksum}",
        ],
        check=True,
    )
    print("OK: image updated")

    return 0


def main():
    returncode = 0
    for release in UBUNTU_RELEASES:
        returncode = max(returncode, update_ubuntu_release(release))

    exit(returncode)


if __name__ == "__main__":
    main()
