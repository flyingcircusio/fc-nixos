{ nixpkgs ? { outPath = (import nixpkgs/lib).cleanSource ./nixpkgs; revCount = 130979; shortRev = "gfedcba"; }
, stableBranch ? false
, supportedSystems ? [ "x86_64-linux" ]
}:

with import nixpkgs/pkgs/top-level/release-lib.nix { inherit supportedSystems; };
with import nixpkgs/lib;

let

  version = fileContents nixpkgs/.version;
  versionSuffix =
    (if stableBranch then "." else "beta") + "${toString (nixpkgs.revCount - 151577)}.${nixpkgs.shortRev}";

  importTest = fn: args: system: import fn ({
    inherit system;
  } // args);

  # test support
  callTestOnMatchingSystems = systems: fn: args:
    forMatchingSystems
      (intersectLists supportedSystems systems)
      (system: hydraJob (importTest fn args system));
  callTest = callTestOnMatchingSystems supportedSystems;

  callSubTests = callSubTestsOnMatchingSystems supportedSystems;
  callSubTestsOnMatchingSystems = systems: fn: args: let
    discover = attrs: let
      subTests = filterAttrs (const (hasAttr "test")) attrs;
    in mapAttrs (const (t: hydraJob t.test)) subTests;

    discoverForSystem = system: mapAttrs (_: test: {
      ${system} = test;
    }) (discover (importTest fn args system));

  in foldAttrs mergeAttrs {} (map discoverForSystem (intersectLists systems supportedSystems));

  pkgs = import nixpkgs { system = "x86_64-linux"; };

  versionModule =
    { system.nixos.versionSuffix = versionSuffix;
      system.nixos.revision = nixpkgs.rev or nixpkgs.shortRev;
    };

  virtualDiskImage =
    { config, lib, pkgs, ... }:
    {
      imports =
        [ nixpkgs/nixos/modules/profiles/clone-config.nix
        ];

      config = {
        system.build.virtualBoxOVA = import nixpkgs/nixos/lib/make-disk-image.nix {
          name = "virtualbox-ova-image";

          inherit pkgs lib config;
          partitionTableType = "legacy";
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
    };

in rec {

  channel = import lib/make-channel.nix { inherit pkgs nixpkgs version versionSuffix; };

  # A bootable VirtualBox virtual appliance as an OVA file (i.e. packaged OVF).
  ova = forMatchingSystems [ "x86_64-linux" ] (system:

    with import nixpkgs { inherit system; };

    hydraJob ((import nixpkgs/nixos/lib/eval-config.nix {
      inherit system;
      modules =
        [ versionModule
          virtualDiskImage
        ];
    }).config.system.build.virtualBoxOVA)

  );

}
