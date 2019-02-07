{ nixpkgs        # path of upstream source tree
, channelSources # initial contents of /root/.nix-defexpr
, contents ? []  # files to be placed inside the image (see make-disk-image.nix)
, version ? "0"
}:

{ config, lib, pkgs, system, ... }:

with lib;
{
  config = {

    system.build.virtualBoxOVA = import ./make-disk-image.nix {
      name = "virtualbox-ova-${version}";

      inherit pkgs lib config nixpkgs channelSources contents;
      diskSize = 10 * 1024;  # MiB

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
          rm $out/nixos.img

          mkdir -p $out/nix-support
          echo "file ova $fn" >> $out/nix-support/hydra-build-products
        '';
      };

    flyingcircus.infrastructureModule = "virtualbox";

  };
}
