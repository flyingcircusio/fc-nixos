import ./make-test-python.nix ({ ... }:
{
  name = "locale";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];

      virtualisation.vlans = [ 3 ];

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:03:01";
          bridged = false;
          networks = {
            "192.168.3.0/24" = [ "192.168.3.1" ];
          };
          gateways = {};
        };
      };

    };

  testScript = ''
    machine.succeed("locale -a | grep -q de_DE.utf8")
    machine.succeed("locale -a | grep -q en_US.utf8")
    machine.succeed('(($(locale -a | wc -l) > 100))')
  '';
})
