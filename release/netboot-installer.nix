{ config, lib, pkgs, system, ... }:

let
  fc_install = pkgs.writeScriptBin "fc-install" ''
#!/bin/sh

# Note:
# the "real" bash for some reason doesn't provide the -e/-i integration
# but running with the system-default /bin/sh does ...

set -eu

function yes_or_no {
    while true; do
        read -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}

udevadm settle

echo "Please review the interface / MAC addresses in the directory"

show-interfaces

read -p "Ready to continue?  [ENTER]"

read -p "ENC wormhole URL: " -e enc_wormhole

curl $enc_wormhole -o /tmp/enc.json

node_name=$(jq -r ".name" /tmp/enc.json)
channel=$(jq -r ".parameters.environment_url" /tmp/enc.json)

console="console=tty0"
# determine console arg
for arg in $(cat /proc/cmdline); do
  if [[ $arg == console* ]]; then
    console="$arg"
    break
  fi
done

echo "Using ''${console}"

lsblk
read -p "Root disk: " -e -i "/dev/sda" root_disk
read -p "Root password: " root_password
root_password=$(echo $root_password | mkpasswd -m sha-512 -s)
read -p "IPMI password: " ipmi_password

echo "Preparing OS disk ..."
umount -R /mnt || true

vgchange -an
vgremove -y vgsys || true
for unused_pv in $(pvs --select "pv_in_use=0" -o pv_name  --reportformat json | jq -r ".report[].pv[].pv_name"); do
  pvremove -y $unused_pv;
done

# Partitioning
if yes_or_no "Wipe whole disk?"; then
  sgdisk $root_disk -Z || true ;
  sgdisk $root_disk -o || true ;
else
  sgdisk $root_disk -d 1 -d 2 -d 3 -d 4;
fi

# There is a somewhat elaborate dance here to support
# reinstalling on machines that use the root/OS device
# also for keeping state (specifically old backup servers)
# we need to ensure that grub and boot are placed early
# on the disk.
sgdisk $root_disk -a 2048 \
  -n 1:1M:+1M -c 1:grub   -t 1:ef02 \
  -n 2:2M:+1G -c 2:boot   -t 2:ea00 \
  -n 3:0:+4G -c 3:swap   -t 3:8200 \
  -n 4:0:0 -c 4:vgsys1 -t 4:8e00

udevadm settle

mkfs -t ext4 -q -E stride=16 -m 1 -F -L boot ''${root_disk}2
mkswap -L swap ''${root_disk}3

pvcreate -ffy -Z y ''${root_disk}4
vgcreate -fy --dataalignment 64k vgsys ''${root_disk}4
vgchange -ay

udevadm settle
lvcreate -ay -L 40G -n root vgsys <<<y
lvcreate -L 16G -n tmp vgsys <<<y

udevadm settle

mkfs.xfs -L root /dev/vgsys/root
mkfs.xfs -L tmp /dev/vgsys/tmp

mount /dev/vgsys/root /mnt

mkdir /mnt/boot
mount ''${root_disk}2 /mnt/boot

mkdir /mnt/tmp
mount /dev/vgsys/tmp /mnt/tmp

cd /mnt

echo "Configuring system ..."

mkdir -p /mnt/etc/nixos

# This version needs to use ./local.nix, but our managed one doesn't!
cat > /mnt/etc/nixos/configuration.nix << __EOF__
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
__EOF__


root_disk_wwn=""
# get unique root disk ID to be used in bootloader later
# not all disks are able to export a WWN ID, fall back to ATA ID
for x in /dev/disk/by-id/wwn-* /dev/disk/by-id/ata-*; do
  if [ "$(realpath $x)" == "''${root_disk}" ]; then
    root_disk_wwn=$x
    break
  fi;
done

if [ "$root_disk_wwn" == "" ]; then
  echo "ERROR: Could not find WWN for root disk"
  exit 1
fi

echo "Found root disk WWN: $root_disk_wwn"

cat > /mnt/etc/nixos/local.nix << __EOF__
{ config, lib, ... }:
{
  boot.loader.grub.device = "''${root_disk_wwn}";
  boot.kernelParams = [ "''${console}" ];

  users.users.root.hashedPassword = "''${root_password}";
}
__EOF__

cp /tmp/enc.json /mnt/etc/nixos/enc.json
# nixos-install will evaluate using /etc/nixos in the installer environment
# and we need the enc there, too.
cp /tmp/enc.json /etc/nixos/enc.json

nix-channel --add $channel nixos
nix-channel --update

export NIX_PATH=/nix/var/nix/profiles/per-user/root/channels/nixos:/nix/var/nix/profiles/per-user/root/channels:nixos-config=/etc/nixos/configuration.nix

echo "Installing ..."

nixos-install --max-jobs 5 --cores 10 -j 10 --no-root-passwd \
  --option substituters "https://cache.nixos.org https://s3.whq.fcio.net/hydra" \
  --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= flyingcircus.io-1:Rr9CwiPv8cdVf3EQu633IOTb6iJKnWbVfCC8x8gVz2o= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="

echo "Setting IPMI password ..."
ipmitool user set password 2 $ipmi_password

echo "Writing channel file ..."
echo "$channel nixos" > /mnt/root/.nix-channels

echo "Cleaning up ..."
cd /
umount -R /mnt

echo "=== Done - reboot at your convenience ==="

	'';

  fc_enter = pkgs.writeScriptBin "fc-enter" ''
#!/bin/sh
set -eu

vgchange -ay vgsys

umount -R /mnt || true

mount /dev/disk/by-label/root /mnt
mount /dev/disk/by-label/tmp /mnt/tmp
mount /dev/disk/by-label/boot /mnt/boot

mount --rbind /dev /mnt/dev
mount --rbind /sys /mnt/sys
mount -t proc /proc /mnt/proc/

nixos-enter --root /mnt

umount -l /mnt/dev
umount -l /mnt/sys
umount -R /mnt

  '';

  show_interfaces = pkgs.writeScriptBin "show-interfaces" ''
#! ${pkgs.python3Full}/bin/python
import json
import subprocess

def run_json(cmd):
    process = subprocess.run(cmd, stdout=subprocess.PIPE, check=True)
    return json.loads(process.stdout)


class Interface(object):

    name = None

    switch = None
    switch_port = None

    mac = None

    def __init__(self):
        self.addresses = []

    @classmethod
    def create(cls, name):
        if name not in interfaces:
            i = Interface()
            i.name = name
            interfaces[name] = i
        return interfaces[name]

interfaces = {}

# get all lldp output
lldp = run_json(['lldpctl', '-f', 'json0'])
if 'interface' in lldp['lldp'][0]:
  for i in lldp['lldp'][0]['interface']:
      interface = Interface.create(i['name'])
      interface.switch = i["chassis"][0]["name"][0]["value"]
      interface.switch_port = "<unknown port>"
      if 'id' in i['port'][0]:
          interface.switch_port = i["port"][0]["id"][0]["value"]
      if 'descr' in i['port'][0]:
          interface.switch_port = i["port"][0]["descr"][0]["value"]

# get all interfaces
ip_l = run_json(['ip', '-j', 'l'])
for l in ip_l:
    if l['link_type'] != 'ether':
        continue
    interface = Interface.create(l['ifname'])
    interface.mac = l['address']

# get all ips
ip_a = run_json(['ip', '-4', '-j', 'a'])
for l in ip_a:
    addrs = []
    for a in l['addr_info']:
        if a['scope'] != 'global':
            continue
        addrs.append(a['local'])
    if not addrs:
        continue
    interface = Interface.create(l['ifname'])
    interface.addresses = addrs

print("INTERFACE           | MAC               | SWITCH               | ADDRESSES")
print("--------------------+-------------------+----------------------+-----------------------------------")
for interface in interfaces.values():
    switch_and_port = f"{interface.switch}/{interface.switch_port}"
    addresses = ', '.join(interface.addresses)
    print(f"{interface.name: <20}| {interface.mac: >17} | {switch_and_port: <20} | {addresses}")

print()
print("NOTE: If you are missing interface data, wait 30s and run `show-interfaces` again.")
print()
'';

  # XXX this is duplicated in fc.secure-erase. I haven't found out how to
  # pull in our overlay here ... -_-
  secure_erase = pkgs.writeScriptBin "fc-secure-erase" ''
#!/bin/sh
set -ex

target="''${1?need target device to erase}"
name="''${target//\//}"
${pkgs.cryptsetup}/bin/cryptsetup open --type plain -d /dev/urandom $target $name
${pkgs.coreutils}/bin/dd if=/dev/zero of=/dev/mapper/$name bs=4M status=progress || true
${pkgs.cryptsetup}/bin/cryptsetup close $name
'';

in
{

  config = {
    nixpkgs.config.allowUnfree = true;

    services.lldpd.enable = true;

    environment.systemPackages = with pkgs; [
      python3Full
      ntp
      megacli
      mdadm
      fc_enter
      jq
      fc_install
      show_interfaces
      secure_erase
      ipmitool
      ethtool
      tcpdump
    ];
    programs.mtr.enable = true;
  };
}
