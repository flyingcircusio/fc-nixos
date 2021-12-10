# This is just a stub to check if backy tools are present and to build on Hydra.
import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:
{
  name = "backyserver";

  machine = {
    imports = [
      ../nixos
      ../nixos/roles
      (testlib.fcConfig { net.fe = false; })
    ];

    flyingcircus.roles.backyserver.enable = true;
    flyingcircus.services.ceph.client.enable = lib.mkForce false;
    flyingcircus.services.consul.enable = lib.mkForce false;
    flyingcircus.enc.name = "machine";

  };

  testScript = ''
    with subtest("backy can be executed"):
      machine.succeed("backy")

    with subtest("backy-extract can be executed"):
      machine.succeed("backy-extract -h")

    with subtest("restore-single-files can be executed"):
      # restore-single-files always has an exit code > 0 in this test setup
      # At least it should not be something we don't expect, like 127 for
      # command not found, for example.
      machine.succeed("restore-single-files; [[ $? == 1 ]]")
  '';
})
