#!/usr/bin/env python3
import crypt
import json
import os
import shlex
import subprocess
import sys
import textwrap
import urllib.request
from pathlib import Path


def run(*args, check=True, **kw):
    print("    cmd> $ " + shlex.join(args))
    kw["check"] = check
    return subprocess.run(args, **kw)


def yes_or_no(prompt):
    while True:
        yn = input(f"{prompt} [y/n]: ")
        if yn in "Yy":
            return True
        if yn in "Nn":
            return False


def prompt(prompt, default=None, options=[]):
    if options:
        options_str = ", ".join(options)
        prompt += f" ({options_str})"
    if default:
        prompt += f" [{default}]"

    prompt = f"{prompt}: "
    result = None
    while not result:
        result = input(prompt)
        if not result:
            result = default
        if options and result not in options:
            result = None
    return result


def udevadm_settle():
    run("udevadm", "settle")


def has_ipmi():
    try:
        run("ipmitool", "mc", "info")
    except Exception:
        return False
    return True


def configure_ipmi():
    if not has_ipmi():
        print("No IPMI controller detected. Skipping IPMI configuration.")
        return

    while True:
        ipmi_password = prompt("IPMI password")

        if len(ipmi_password) > 16:
            print(
                f"IPMI passwords must be shorter than 16 characters. Your password has {len(ipmi_password)} characters."
            )
            continue

        try:
            run("ipmitool", "user", "test", "2", "16", ipmi_password)
        except Exception:
            pass
        else:
            print("Password already active. Skipping update.")
            break

        try:
            print("Setting IPMI user and password ...")
            run("ipmitool", "user", "set", "password", "2", ipmi_password)
            break
        except Exception:
            print(
                f"""
Setting the IPMI password failed.

A NOTE ABOUT IPMI PASSWORD LENGTHS
==================================

IPMI 1.5 and IPMI 2.0 prescribe maximum password lengths of 16 and 20
characters.
Additionally, some systems cut off after those lengths, others complain with
ominous errors.

The password you've given is {len(ipmi_password)} characters long.

We suggest trying different password lengths if 16 or 20 doesn't work.

Enter "<skip>" if you want to skip this step.

"""
            )
    run("ipmitool", "user", "set", "name", "2", "ADMIN")


def main():
    udevadm_settle()
    run("umount", "-R", "/mnt", check=False)

    print("Please review the interface / MAC addresses in the directory")

    run("show-interfaces")

    input("Ready to continue? [ENTER]")

    enc_wormhole = input("ENC wormhole URL: ")

    with urllib.request.urlopen(enc_wormhole) as enc_response:
        enc = json.load(enc_response)

    channel = enc["parameters"]["environment_url"]

    console = "console=tty0"
    with open("/proc/cmdline") as f:
        cmdline = f.read()
    for arg in cmdline.split(" "):
        if arg.startswith("console="):
            console = arg
            break

    print(f"Using {console}")

    run("lsblk")

    root_disk = prompt("Root disk", "/dev/sda")
    root_password = prompt("Root password")
    root_password = crypt.crypt(
        root_password, salt=crypt.mksalt(crypt.METHOD_SHA512)
    )

    configure_ipmi()

    if Path("/sys/firmware/efi").exists():
        boot_style_default = "efi"
    else:
        boot_style_default = "bios"

    boot_style = prompt("Boot style", boot_style_default, ["efi", "bios"])

    # Variables for BIOS/EFI boot styles
    if boot_style == "efi":
        boot_partition_type = "ef00"
        boot_fs_type = "vfat"
    elif boot_style == "bios":
        boot_partition_type = "ea00"
        boot_fs_type = "ext4"
    else:
        raise ""

    print("Preparing OS disk ...")
    run("vgchange", "-an")
    run("vgremove", "-y", "vgsys", check=False)

    pvs = run(
        "pvs",
        "--select",
        "pv_in_use=0",
        "-o",
        "pv_name",
        "--reportformat",
        "json",
        stdout=subprocess.PIPE,
        check=False,
    )
    pvs = json.loads(pvs.stdout)
    for report in pvs["report"]:
        for unused_pv in report["pv"]:
            run("pvremove", "-y", unused_pv["pv_name"])

    # Partitioning
    if yes_or_no("Wipe whole disk?"):
        run("sgdisk", root_disk, "-Z", check=False)
        run("sgdisk", root_disk, "-o", check=False)
    else:
        run(
            "sgdisk",
            root_disk,
            "-d",
            "1",
            "-d",
            "2",
            "-d",
            "3",
            "-d",
            "4",
            check=False,
        )

    # There is a somewhat elaborate dance here to support
    # reinstalling on machines that use the root/OS device
    # also for keeping state (specifically old backup servers)
    # we need to ensure that grub and boot are placed early
    # on the disk.
    #
    # We keep creating swap and grub partitions just out of an abundance of
    # caution and to stay in line with the long term partition numbers - even
    # though we've been using symbolic names for a long time now everywhere.
    run(
        "sgdisk",
        root_disk,
        "-a",
        "2048",
        "-n",
        "1:1M:+1M",
        "-c",
        "1:grub",
        "-t",
        "1:ef02",
        "-n",
        "2:2M:+1G",
        "-c",
        "2:boot",
        "-t",
        f"2:{boot_partition_type}",
        "-n",
        "3:0:+4G",
        "-c",
        "3:swap",
        "-t",
        "3:8200",
        "-n",
        "4:0:0",
        "-c",
        "4:vgsys1",
        "-t",
        "4:8e00",
    )

    udevadm_settle()

    run("wipefs", "-a", "-f", "/dev/disk/by-partlabel/boot")
    if boot_fs_type == "vfat":
        run("mkfs.vfat", "-n", "boot", "/dev/disk/by-partlabel/boot")
    elif boot_fs_type == "ext4":
        run(
            "mkfs",
            "-t",
            boot_fs_type,
            "-q",
            "-L",
            "boot",
            "/dev/disk/by-partlabel/boot",
        )

    run("pvcreate", "-ffy", "-Z", "y", "/dev/disk/by-partlabel/vgsys1")

    run("vgcreate", "-fy", "vgsys", "/dev/disk/by-partlabel/vgsys1")
    run("vgchange", "-ay")

    udevadm_settle()

    run(
        "lvcreate",
        "-ay",
        "-L",
        "80G",
        "-n",
        "root",
        "vgsys",
        input="y\n",
        encoding="ascii",
    )
    run(
        "lvcreate",
        "-ay",
        "-L",
        "16G",
        "-n",
        "tmp",
        "vgsys",
        input="y\n",
        encoding="ascii",
    )

    udevadm_settle()

    run("mkfs.xfs", "-L", "root", "/dev/vgsys/root")
    run("mkfs.xfs", "-L", "tmp", "/dev/vgsys/tmp")

    run("mount", "/dev/vgsys/root", "/mnt")

    Path("/mnt/boot").mkdir(parents=True, exist_ok=True)
    run("mount", "/dev/disk/by-partlabel/boot", "/mnt/boot")

    Path("/mnt/tmp").mkdir(parents=True, exist_ok=True)
    run("mount", "/dev/vgsys/tmp", "/mnt/tmp")

    os.chdir("/mnt")

    print("Configuring system ...")

    Path("/mnt/etc/nixos").mkdir(parents=True, exist_ok=True)

    # # This version needs to use ./local.nix, but our managed one doesn't!
    with Path("/mnt/etc/nixos/configuration.nix").open("w") as f:
        f.write(
            textwrap.dedent(
                """\
        {
          imports = [
            <fc/nixos>
            <fc/nixos/roles>
            ./local.nix
          ];

          flyingcircus.infrastructureModule = "flyingcircus-physical";

          # Options for first boot. This file will be replaced after the first
          # activation/rebuild.
          flyingcircus.agent.updateInMaintenance = false;
          systemd.timers.fc-agent.timerConfig.OnBootSec = "1s";

        }
        """
            )
        )

    root_disk_stable_path = ""
    # get unique root disk ID to be used in bootloader later
    # we prefer getting a wwn or nvme-eui but fall back to whatever stable identifier
    # we can get.
    disk_id_path = Path("/dev/disk/by-id/")
    candidates = []
    candidates.extend(disk_id_path.glob("nvme-eui.*"))
    candidates.extend(disk_id_path.glob("wwn-*"))
    candidates.extend(disk_id_path.glob("*"))
    for candidate in candidates:
        if candidate.resolve() == Path(root_disk):
            root_disk_stable_path = candidate
            break
    else:
        print(f"Could not find stable path for root disk at {root_disk}")
        sys.exit(1)

    print(f"Found stable root disk path: {root_disk_stable_path}")

    with Path("/mnt/etc/nixos/local.nix").open("w") as f:
        f.write(
            textwrap.dedent(
                f"""
        {{ config, lib, ... }}:
        {{
          boot.loader.grub.device = "{root_disk_stable_path}";
          boot.kernelParams = [ "{console}" ];

          users.users.root.hashedPassword = "{root_password}";

          flyingcircus.boot-style = "{boot_style}";
        }}
        """
            )
        )

    with Path("/mnt/etc/nixos/enc.json").open("w") as f:
        json.dump(enc, f)

    # nixos-install will evaluate using /etc/nixos in the installer environment
    # and we need the enc there, too.
    with Path("/etc/nixos/enc.json").open("w") as f:
        json.dump(enc, f)

    run("nix-channel", "--add", channel, "nixos")
    run("nix-channel", "--update")

    os.environ["NIX_PATH"] = ":".join(
        [
            "/nix/var/nix/profiles/per-user/root/channels/nixos",
            "/nix/var/nix/profiles/per-user/root/channels",
            "nixos-config=/etc/nixos/configuration.nix",
        ]
    )

    print("Installing ...")

    run(
        "nixos-install",
        "--max-jobs",
        "5",
        "--cores",
        "10",
        "-j",
        "10",
        "--no-root-passwd",
        "--option",
        "substituters",
        "https://cache.nixos.org https://s3.whq.fcio.net/hydra",
        "--option",
        "trusted-public-keys",
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= flyingcircus.io-1:Rr9CwiPv8cdVf3EQu633IOTb6iJKnWbVfCC8x8gVz2o= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=",
    )

    print("Writing channel file ...")
    with Path("/mnt/root/.nix-channels").open("w") as f:
        f.write(f"{channel} nixos")

    print("Cleaning up ...")

    os.chdir("/")
    run("umount", "-R", "/mnt")

    print("=== Done - reboot at your convenience ===")


if __name__ == "__main__":
    main()
