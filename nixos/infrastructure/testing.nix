# Absolute minimum infrastructure defition for running tests etc.
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
    security.rngd.enable = false;
    services.haveged.enable = true;  # use pseudo-entropy to speed up tests
    services.openssh.enable = lib.mkOverride 60 false;
    # build-vms.nix from NixOS automatically generates numbered interface
    # configs with default IPs. We rename the devices to fe and srv early so
    # the services wait for eth1 and eth2 for 5 minutes and time out.
    # This is annoying when other services depend on network.target.
    systemd.services = lib.mkIf (config.flyingcircus.enc.parameters ? interfaces) {
      network-addresses-eth1 = lib.mkForce {};
      network-addresses-eth2 = lib.mkForce {};
    };
  };
}
