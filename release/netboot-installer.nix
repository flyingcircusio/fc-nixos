{ config, lib, pkgs, system, ... }:

let
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
      (pkgs.callPackage ../pkgs/fc/install {})
      show_interfaces
      secure_erase
      ipmitool
      ethtool
      tcpdump
    ];
    programs.mtr.enable = true;
  };
}
