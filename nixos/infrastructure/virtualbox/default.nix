{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "virtualbox") {
    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
    };

    boot.growPartition = lib.mkDefault true;
    boot.loader.grub.device = lib.mkDefault "/dev/sda";

    virtualisation.virtualbox.guest.enable = lib.mkDefault true;

    users.users.root.password = "";
  };
}
