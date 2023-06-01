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
    "nixos-dev-vm-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
  fileName = "${name}.qcow2";

in
{
  config = {
    # telegraf service doesn't work on initial boot and is unneeded, disable it
    services.telegraf.enable = mkForce false;

    boot.loader.grub.device = lib.mkForce "/dev/vda";

    flyingcircus.enc.name = "dev-vm";
    flyingcircus.infrastructureModule = "dev-vm";

    systemd.timers.fc-agent.timerConfig.OnBootSec = "1s";

    system.build.devVMImage = import ./make-disk-image.nix {
      inherit pkgs lib config channelSources configFile contents name;
      rootLabel = "root";
      diskSize = 25600;
      format = "qcow2-compressed";
      filename-prefix = name;
      postVM = ''
        echo "creating Flying Circus VM image..."
        mkdir -p $out
        mkdir $out/nix-support
        echo "file img $out/${fileName}" >> $out/nix-support/hydra-build-products
      '';
    };
  };
}
