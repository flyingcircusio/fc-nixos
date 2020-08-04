# This is just a stub to check if sensu-client builds and to cache the result.
# We need to port sensu server for a real end-to-end test.
import ./make-test-python.nix ({ pkgs, lib, ... }:
{
  name = "sensu-client";

  machine = {
    imports = [ ../nixos ];

    # Hydra fails when trying to build the local sensu
    # config which is referenced in the start script so
    # we have to patch it here...
    systemd.services.sensu-client.script = lib.mkForce "sleep 100";

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
