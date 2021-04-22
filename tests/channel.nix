# Does our custom combined channel work as expected?
# Inspired by the installer.nix test from upstream.
with builtins;

import ./make-test-python.nix ({ pkgs, lib, ... }:
let
  release = import ../release {};
  channel = release.release.src;

in {
  name = "channel";

  machine = {
    imports = [ ../nixos ];

    environment.systemPackages = with pkgs; [
      # Pre-install it to make it possible to install the package in the test script
      # without the need to download stuff (which fails in a test, of course).
      lamp_php56
    ];

    environment.etc."nixpkgs-paths-debug".text = toJSON {
      pkgs = "${pkgs.path}";
      releaseChannelSrc = "${channel}";
      nixpkgs = "${<nixpkgs>}";
    };

    users.users.alice = {
      isNormalUser = true;
      home = "/home/alice";
    };

    virtualisation.memorySize = 3000;
  };

  testScript = ''
    print(machine.succeed("cat /etc/nixpkgs-paths-debug | ${pkgs.jq}/bin/jq"))
    machine.execute("ln -s ${channel} /nix/var/nix/profiles/per-user/root/channels")

    with subtest("Root should be able to nix-env install from nixpkgs"):
      machine.succeed("nix-env -iA nixos.procps")

    with subtest("Root should be able to nix-env install from fc"):
      machine.succeed("nix-env -iA nixos.fc.logcheckhelper")

    with subtest("Non-root should be able to nix-env install from nixpkgs"):
      machine.succeed("su alice -l -c 'nix-env -iA nixos.procps'")

    with subtest("Non-root should be able to nix-env install from fc"):
      machine.succeed("su alice -l -c 'nix-env -iA nixos.fc.logcheckhelper'")

    with subtest("Installing php56 with dependencies on a legacy channel should work"):
      # This also fixes `nix-env -qa` in the next subtest somehow...
      machine.succeed("nix-env -iA nixos.lamp_php56")

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
