import ./make-test.nix ({ version ? "7", pkgs, ... }:
let
  ipv4 = "192.168.1.1";
in
{
  name = "elasticsearch";

  machine =
    { pkgs, config, ... }:
    {

      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          networks = {
            "192.168.1.0/24" = [ ipv4 ];
          };
          gateways = {};
        };
      };

      networking.domain = "test";
      virtualisation.memorySize = 3072;
      virtualisation.qemu.options = [ "-smp 2" ];
      flyingcircus.roles."elasticsearch${version}".enable = true;
      flyingcircus.roles.elasticsearch.esNodes = [ "machine" ];
    };

  testScript = ''
    $machine->waitForUnit("elasticsearch");
    $machine->waitUntilSucceeds("curl ${ipv4}:9200");
  '';
})
