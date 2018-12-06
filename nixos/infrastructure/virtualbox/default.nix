{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "virtualbox") {
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
    };

    boot.growPartition = true;
    boot.loader.grub.fsIdentifier = "provided";
    boot.loader.grub.device = "/dev/sda";

    users.users.root.password = "";

    virtualisation.virtualbox.guest.enable = true;
  };
}
