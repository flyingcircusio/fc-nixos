{ nixpkgs        # path of upstream source tree
, channelSources # initial content of /root/.nix-defexprs/channels/nixos
, configFile     # initial /etc/nixos/configuration.nix
, contents ? []  # files to be placed inside the image (see make-disk-image.nix)
, version ? "0"
}:

{ config, lib, pkgs, system, ... }:

with lib;

let
  name =
    "nixos-fc-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
  fileName = "${name}.img.lz4";

in
{
  config = {

    # use /dev/disk/device-by-alias/root later on, but this is not available
    # at this stage
    boot.loader.grub.device = lib.mkForce "/dev/vda";

    # telegraf service doesn't work on initial boot and is unneeded, disable it
    services.telegraf.enable = mkForce false;

    flyingcircus.infrastructureModule = "flyingcircus";

    system.build.fcImage = import ./make-disk-image.nix {
      inherit pkgs lib config channelSources configFile contents name;
      rootLabel = "root";
      diskSize = 10240;
      postVM = ''
          echo "creating Flying Circus VM image..."
          mkdir -p $out
          fn=$out/${fileName}
          ${pkgs.lz4}/bin/lz4 $diskImage $fn
          rm $diskImage
          mkdir $out/nix-support
          echo "file img $fn" >> $out/nix-support/hydra-build-products
        '';
      };
  };

}
