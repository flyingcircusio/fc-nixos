{ nixpkgs        # path of upstream source tree
, channelSources # initial content of /root/.nix-defexprs/channels/nixos
, configFile     # initial /etc/nixos/configuration.nix
, contents ? []  # files to be placed inside the image (see make-disk-image.nix)
, version ? "0"
, infrastructureModule ? "virtualbox"
}:

{ config, lib, pkgs, system, ... }:

with lib;

let
  cfg = config.virtualbox;

in {
  imports = [ "${nixpkgs}/nixos/modules/virtualisation/virtualbox-image.nix" ];

  config = {

    flyingcircus.infrastructureModule = infrastructureModule;

    system.build.ovaImage = import ./make-disk-image.nix {
      name = cfg.vmDerivationName;

      inherit pkgs lib config channelSources configFile contents;
      diskSize = cfg.baseImageSize;

      # copied from nixos/modules/virtualisation/virtualbox-image.nix
      postVM =
        ''
          export HOME=$PWD
          export PATH=${pkgs.virtualbox}/bin:$PATH

          echo "creating VirtualBox pass-through disk wrapper (no copying invovled)..."
          VBoxManage internalcommands createrawvmdk -filename disk.vmdk -rawdisk $diskImage

          echo "creating VirtualBox VM..."
          vmName="${cfg.vmName}";
          VBoxManage createvm --name "$vmName" --register \
            --ostype ${if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then "Linux26_64" else "Linux26"}
          VBoxManage modifyvm "$vmName" \
            --memory ${toString cfg.memorySize} --acpi on --vram 32 \
            ${optionalString (pkgs.stdenv.hostPlatform.system == "i686-linux") "--pae on"} \
            --nictype1 virtio --nic1 nat \
            --audiocontroller ac97 --audio alsa \
            --rtcuseutc on \
            --usb on --mouse usbtablet
          VBoxManage storagectl "$vmName" --name SATA --add sata --portcount 4 --bootable on --hostiocache on
          VBoxManage storageattach "$vmName" --storagectl SATA --port 0 --device 0 --type hdd \
            --medium disk.vmdk

          echo "exporting VirtualBox VM..."
          mkdir -p $out
          fn="$out/${cfg.vmFileName}"
          VBoxManage export "$vmName" --output "$fn"
          rm $diskImage

          mkdir $out/nix-support
          echo "file ova $fn" >> $out/nix-support/hydra-build-products
        '';
      };

  };
}
