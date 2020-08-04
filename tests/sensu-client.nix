# This is just a stub to check if sensu-client builds and to cache the result.
# We need to port sensu server for a real end-to-end test.
import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "sensu-client";

  machine = {
    imports = [ ../nixos ];

    flyingcircus.services.sensu-client = {
      password = "sensu";
      server = "127.0.0.1";
      enable = true;
    };
  };

  testScript = ''
    start_all()
  '';
})
