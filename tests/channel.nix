# Does our custom combined channel work as expected?
# Inspired by the installer.nix test from upstream.
# This also serves as an example on how to run nixos-rebuild
# inside a NixOS test VM.
with builtins;

import ./make-test-python.nix ({ pkgs, lib, ... }:
let
  release = import ../release {};
  channel = release.release.src;

in {
  name = "channel";

  machine = {
    imports = [ ../nixos ../nixos/roles ];

    flyingcircus.enc.parameters = {
      resource_group = "test";
      interfaces.srv = {
        mac = "52:54:00:12:34:56";
        bridged = false;
        networks = {
          "192.168.101.0/24" = [ "192.168.101.1" ];
          "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
        };
        gateways = {};
      };
    };

    environment.systemPackages = with pkgs; [
      # Pre-install it to make it possible to install the package in the test script
      # without the need to download stuff (which fails in a test, of course).
    ];

    environment.etc."nixpkgs-paths-debug".text = toJSON {
      pkgs = "${pkgs.path}";
      releaseChannelSrc = "${channel}";
      nixpkgs = "${<nixpkgs>}";
    };

    environment.etc."nixos/local.nix".text = ''
      { ... }:
      {
        # Only a dummy to make nixos-rebuild inside the test VM work.
      }
    '';

    environment.etc."local/nixos/synced_config.nix".text = ''
      { config, pkgs, lib, ... }:
      {
        # !!! If you use this test as a template for another test that wants to
        # use nixos-rebuild inside the VM:
        # You may have to change config here (used for rebuilds inside the VM)
        # when you change settings on the "outside" (used to build the VM on the test host).
        # Configs need to be in sync or nixos-rebuild will try to build
        # more stuff which may fail because networking isn't available inside
        # the test VM.

        services.telegraf.enable = false;

        users.users.alice = {
          isNormalUser = true;
          home = "/home/alice";
        };
      }
    '';

    system.extraDependencies = with pkgs; [
      # Taken from nixpkgs tests/ec2.nix
      busybox
      cloud-utils
      desktop-file-utils
      libxslt.bin
      mkinitcpio-nfs-utils
      stdenv
      stdenvNoCC
      texinfo
      unionfs-fuse
      xorg.lndir
      # Our custom stuff that's needed to rebuild the VM.
      lamp_php73
      lamp_php73.packages.composer
      channel
    ];

    users.users.alice = {
      isNormalUser = true;
      home = "/home/alice";
    };

    # nix-env -qa needs a lot of RAM. Crashed with 2000.
    virtualisation.memorySize = 3000;
    virtualisation.qemu.options = [ "-smp 2" ];
  };

  testScript = ''
    print(machine.succeed("cat /etc/nixpkgs-paths-debug | ${pkgs.jq}/bin/jq"))
    machine.execute("ln -s ${channel} /nix/var/nix/profiles/per-user/root/channels")

    with subtest("Root should be able to nix-env install from nixpkgs"):
      machine.succeed("nix-env -iA nixos.procps")

    with subtest("Building the system should work"):
      machine.succeed("nix-build '<nixpkgs/nixos>' -A system --option substitute false")

    with subtest("Root should be able to nix-env install from fc"):
      machine.succeed("nix-env -iA nixos.fc.logcheckhelper")

    with subtest("Non-root should be able to nix-env install from nixpkgs"):
      machine.succeed("su alice -l -c 'nix-env -iA nixos.procps'")

    with subtest("Non-root should be able to nix-env install from fc"):
      machine.succeed("su alice -l -c 'nix-env -iA nixos.fc.logcheckhelper'")

    with subtest("Non-root should be able to use nix-env -qa to list packages"):
      machine.succeed("su alice -l -c 'nix-env -qa'")

    with subtest("login/nix-env -i should remove the 19.03 channel hack"):
      # This is the situation after an upgrade from 19.03 to this version.
      machine.execute("rm -f /home/alice/.nix-defexpr/*")
      machine.execute("ln -s /var/empty /home/alice/.nix-defexpr/nixos")
      machine.succeed("su alice -l -c 'nix-env -iA nixos.procps'")

    with subtest("login/nix-env -i should fix an empty .nix-defexpr"):
      # This is the situation after an upgrade from 19.03 to a version with the
      # bug introduced by commit e118d06114be2d7d6414428db2d3b5608fe64bb5
      machine.execute("rm -f /home/alice/.nix-defexpr/*")
      machine.succeed("su alice -l -c 'nix-env -iA nixos.procps'")
  '';
})
