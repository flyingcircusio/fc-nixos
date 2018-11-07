{ nixpkgs         # path of upstream source tree
, channelSources  # initial contents of /root/.nix-defexpr
}:

{ config, lib, pkgs, system, ... }:

with lib;
{
  imports =
    [ # "${nixpkgs}/nixos/modules/profiles/minimal.nix"
    ];

  config = {
    system.build.virtualBoxOVA = import ./make-disk-image.nix {
      name = "virtualbox-ova-image";

      inherit pkgs lib config nixpkgs channelSources;
      diskSize = 5 * 1024;  # MiB

      postVM =
        ''
          export HOME=$PWD
          export PATH=${pkgs.virtualbox}/bin:$PATH

          VBoxManage internalcommands createrawvmdk -filename disk.vmdk -rawdisk $diskImage
          echo "creating VirtualBox VM..."
          vmName="NixOS VBox dev VM";
          VBoxManage createvm --name "$vmName" --register \
            --ostype ${if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then "Linux26_64" else "Linux26"}
          VBoxManage modifyvm "$vmName" \
            --memory 1536 --acpi on --vram 32 \
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
          fn="$out/nixos-dev.ova"
          VBoxManage export "$vmName" --output "$fn"

          mkdir -p $out/nix-support
          echo "file ova $fn" >> $out/nix-support/hydra-build-products
        '';
      };

    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
    };

    boot.growPartition = true;
    boot.loader.grub.fsIdentifier = "provided";
    boot.loader.grub.device = "/dev/sda";

    users.users.root.password = "";

    virtualisation.virtualbox.guest.enable = true;

    system.stateVersion = mkDefault "18.09";
  };
}
