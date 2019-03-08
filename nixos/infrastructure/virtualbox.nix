{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "virtualbox") {
    boot.growPartition = lib.mkDefault true;
    boot.loader.grub.device = lib.mkDefault "/dev/sda";

    fileSystems."/" = lib.mkOverride 90 {
      fsType = "xfs";
      device = "/dev/disk/by-label/nixos";
    };

    users.users.root.password = "";

    virtualisation.virtualbox.guest.enable = lib.mkDefault true;
    zramSwap.enable = true;
  };
}
