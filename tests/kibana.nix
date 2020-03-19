import ./make-test.nix ({ pkgs, ... }:
let
  ipv4 = "192.168.101.1";
in
{
  name = "kibana";

  machine =
    { pkgs, config, ... }:
    {

      imports = [ ../nixos ../nixos/roles ];

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
          };
          gateways = {};
        };
      };

      virtualisation.memorySize = 3072;
      virtualisation.qemu.options = [ "-smp 2" ];
      flyingcircus.roles.elasticsearch6.enable = true;
      flyingcircus.roles.kibana.enable = true;
    };

  testScript = ''
    startAll;

    $machine->waitForUnit("elasticsearch");
    $machine->waitForUnit("kibana");

    my $statusCheck = <<'END';
      for count in {0..100}; do
        echo "Checking..." | logger -t kibana-status
        curl -s "${ipv4}:5601/api/status" | grep -q '"state":"green' && exit
        sleep 5
      done
      echo "Failed" | logger -t kibana-status
      curl -s "${ipv4}:5601/api/status"
      exit 1
    END

    subtest "cluster healthy?", sub {
      $machine->succeed($statusCheck);
    };

    subtest "killing the kibana process should trigger an automatic restart", sub {
      $machine->succeed("kill -9 \$(systemctl show kibana.service --property MainPID --value)");
      $machine->waitForUnit("kibana");
      $machine->succeed($statusCheck);
    };
  '';
})
