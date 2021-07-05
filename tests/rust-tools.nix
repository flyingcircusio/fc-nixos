# This is just a stub to check if our rust tools build and to cache them.
import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "rust-tools";

  machine = {
    imports = [ ../nixos ];

    environment.systemPackages = with pkgs; [
      fc.check-age
      fc.check-postfix
      fc.logcheckhelper
      fc.multiping
      fc.roundcube-chpasswd
      fc.sensusyntax
      fc.userscan
    ];

    config.services.telegraf.enable = false;

  };

  testScript = ''
    with subtest("check_age"):
      machine.succeed("check_age -h")

    with subtest("check-postfix"):
      machine.succeed("check_mailq -h")

    with subtest("logcheck-helper"):
      machine.succeed("logcheck-helper -h")

    with subtest("multiping"):
      machine.succeed("multiping -h")

    with subtest("userscan"):
      machine.succeed("fc-userscan -h")

    with subtest("userscan"):
      machine.succeed("fc-userscan -h")
  '';
})
