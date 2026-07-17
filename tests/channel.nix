# Does our custom combined channel work as expected?
# Inspired by the installer.nix test from upstream.
with builtins;

import ./make-test-python.nix (
  {
    pkgs,
    lib,
    testlib,
    ...
  }:
  let
    release = import ../release { };
    channel = release.release.src;

  in
  {
    name = "channel";

    nodes.machine = {
      imports = [ (testlib.fcConfig { }) ];

      environment.etc."nixpkgs-paths-debug".text = toJSON {
        pkgs = "${pkgs.path}";
        releaseChannelSrc = "${channel}";
        nixpkgs = "${<nixpkgs>}";
      };

      users.users.alice = {
        isNormalUser = true;
        home = "/home/alice";
      };

      # Crashed with 4000.
      virtualisation.memorySize = 5000;
      virtualisation.qemu.options = [ "-smp 2" ];
    };

    testScript = ''
      print(machine.succeed("cat /etc/nixpkgs-paths-debug | ${pkgs.jq}/bin/jq"))
      machine.execute("mkdir -p /nix/var/nix/profiles/per-user/root")
      machine.execute("ln -s ${channel} /nix/var/nix/profiles/per-user/root/channels")

      # This package must have all outputs cached in the /nix/store of the VM test
      with subtest("Root should be able to nix-env install from nixpkgs"):
        machine.succeed("nix-env -iA nixos.tmux")

      with subtest("Root should be able to nix-env install from fc"):
        machine.succeed("nix-env -iA nixos.fc.logcheckhelper")

      with subtest("Non-root should be able to nix-env install from nixpkgs"):
        machine.succeed("su alice -l -c 'nix-env -iA nixos.tmux'")

      with subtest("Non-root should be able to nix-env install from fc"):
        machine.succeed("su alice -l -c 'nix-env -iA nixos.fc.logcheckhelper'")

      with subtest("login/nix-env -i should remove the 19.03 channel hack"):
        # This is the situation after an upgrade from 19.03 to this version.
        machine.execute("rm -f /home/alice/.nix-defexpr/*")
        machine.execute("ln -s /var/empty /home/alice/.nix-defexpr/nixos")
        machine.succeed("su alice -l -c 'nix-env -iA nixos.tmux'")

      with subtest("login/nix-env -i should fix an empty .nix-defexpr"):
        # This is the situation after an upgrade from 19.03 to a version with the
        # bug introduced by commit e118d06114be2d7d6414428db2d3b5608fe64bb5
        machine.execute("rm -f /home/alice/.nix-defexpr/*")
        machine.succeed("su alice -l -c 'nix-env -iA nixos.tmux'")
    '';
  }
)
