# Absolute minimum infrastructure definition for running tests etc.
{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "testing") {
    boot.loader.grub.device = "/dev/sda";
    fileSystems."/".device = "/dev/disk/by-label/nixos";
    networking.useDHCP = lib.mkForce false;
    users.users.root.password = "";

    flyingcircus.agent.enable = lib.mkOverride 200 false;
    flyingcircus.enc = {
      parameters.resource_group = "testrg";
      parameters.location = "testloc";
      name = "testvm";
    };
    services.haveged.enable = true;  # use pseudo-entropy to speed up tests
    services.openssh.enable = lib.mkOverride 60 false;
    # build-vms.nix from NixOS automatically generates numbered interface
    # configs with default IPs. We rename the devices to fe and srv early so
    # the services wait for the interfaces for 5 minutes and time out.
    # This is annoying when other services depend on network.target.
    systemd.services = lib.mkIf (config.flyingcircus.enc.parameters ? interfaces) {
      network-addresses-eth0 = lib.mkForce {};
      network-addresses-eth1 = lib.mkForce {};
      network-addresses-eth2 = lib.mkForce {};
      network-addresses-eth3 = lib.mkForce {};
      network-addresses-eth4 = lib.mkForce {};
      network-addresses-eth5 = lib.mkForce {};
      network-addresses-eth6 = lib.mkForce {};
      network-addresses-eth7 = lib.mkForce {};
      network-addresses-eth8 = lib.mkForce {};
      network-addresses-eth9 = lib.mkForce {};
    };
  };
}
