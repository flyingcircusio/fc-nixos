import ./make-test.nix ({ pkgs, lib, ... }:
let

  netLoc4Srv = "10.0.1";
  turnserver4Srv = netLoc4Srv + ".2";

  netLoc6Srv = "2001:db8:1::";
  turnserver6Srv = netLoc6Srv + "2";

  net4Fe = "10.0.3";
  client4Fe = net4Fe + ".1";
  turnserver4Fe = net4Fe + ".2";

  net6Fe = "2001:db8:3::";
  client6Fe = net6Fe + "1";
  turnserver6Fe = net6Fe + "2";

  turnserverFe = "turnserver.fe.loc.fcio.net";

  hosts = ''
    127.0.0.1 localhost
    ::1 localhost

    ${turnserver6Fe} ${turnserverFe}
    ${turnserver4Fe} ${turnserverFe}
  '';

in {
  name = "coturn";
  nodes = {
    client = {
      imports = [ ../nixos ../nixos/roles ];
      environment.systemPackages = [ pkgs.curl ];

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.fe = {
          mac = "52:54:00:12:02:01";
          networks = {
            "${net4Fe}.0/24" = [ client4Fe ];
            "${net6Fe}/64" = [ client6Fe ];
          };
          gateways = {};
        };
      };
      virtualisation.vlans = [ 1 2 ];
    };

    turnserver =
      { config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.coturn.enable = true;

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:01:02";
            networks = {
              "${netLoc4Srv}.0/24" = [ turnserver4Srv ];
              "${netLoc6Srv}/64" = [ turnserver6Srv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:02";
            networks = {
              "${net4Fe}.0/24" = [ turnserver4Fe ];
              "${net6Fe}/64" = [ turnserver6Fe ];
            };
            gateways = {};
          };
        };

        environment.etc.hosts.text = lib.mkForce hosts;
        networking.domain = "fcio.net";
        networking.firewall.allowedTCPPorts = [ 5349 ];
        virtualisation.vlans = [ 1 2 ];
      };
  };

  testScript = { nodes, ... }:
  let
    config = nodes.turnserver.config;
    sensuChecks = config.flyingcircus.services.sensu-client.checks;
    coturnCheck = lib.replaceChars ["\n"] [" "] sensuChecks.coturn.command;
  in ''
    $turnserver->waitForUnit("coturn.service");
    $turnserver->waitForOpenPort(3478);
    $turnserver->waitForOpenPort(3479);
    $turnserver->waitForOpenPort(5349);
    $turnserver->waitForOpenPort(5350);

    subtest "coturn should be reachable on fe (IPv4)", sub {
      $client->waitUntilSucceeds('nc -z ${turnserver4Fe} 5349');
    };

    subtest "coturn should be reachable on fe (IPv6)", sub {
      $client->waitUntilSucceeds('nc -z ${turnserver6Fe} 5349');
    };

    subtest "sensu check should be green", sub {
      $turnserver->succeed("${coturnCheck}");
    };

    subtest "sensu check should be red after shutting down coturn", sub {
      $turnserver->stopJob("coturn.service");
      $turnserver->waitUntilFails("nc -z localhost 5349");
      $turnserver->mustFail("${coturnCheck}");
    };

    subtest "service user should be able to write to local config dir", sub {
      $turnserver->succeed('sudo -u turnserver touch /etc/local/coturn/config.json');
    };

    # look for coturn's 4 default ports. Order is:
    # (listening-port, alt-listening-port, tls-listening-port, alt-tls-listening-port)

    subtest "coturn opens no unexpected ports", sub {
      $turnserver->mustFail("netstat -tlpn | grep turnserver | egrep -qv ':3478 |:3479 |:5349 |:5350 '");
    };

  '';
})
