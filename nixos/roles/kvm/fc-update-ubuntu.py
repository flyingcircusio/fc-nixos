#!/usr/bin/env python3
from hashlib import file_digest
from os import chdir
from pathlib import Path
from socket import gethostname
from subprocess import DEVNULL, run
from sys import exit
from tempfile import TemporaryDirectory
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
    ),
    UbuntuReleaseMetadata(
        environment="26.04-lts-resolute-raccoon",
        base="https://cloud-images.ubuntu.com/resolute/current",
        image="resolute-server-cloudimg-amd64.img",
    ),
]


def update_ubuntu_release(release: UbuntuReleaseMetadata) -> int:

    print(f"Updating {release.environment}")
    namespaces = run(
        ["rbd", "namespace", "list", "rbd.hdd"],
        check=True,
        text=True,
        capture_output=True,
    ).stdout.splitlines()
    if "images-ubuntu" not in (n.strip() for n in namespaces):
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
    checksums = Path("SHA256SUMS").read_text().splitlines()
    checksum = None
    for line in checksums:
        if release.image not in line:
            continue
        checksum = line.split(" ")[0]
        break
    assert checksum

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
    with open(release.image, "rb") as imgfile:
        got_checksum = file_digest(imgfile, "sha256").hexdigest()

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
        with TemporaryDirectory() as tmpdir:
            # always work in a fresh directory per release, to avoid issues
            # with conflicting file names
            chdir(tmpdir)
            returncode = max(returncode, update_ubuntu_release(release))

    exit(returncode)


if __name__ == "__main__":
    main()
