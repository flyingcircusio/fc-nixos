# This test has been broken but still signaled "green" earlier on.
# I have disabled it for now.
import ./make-test-python.nix ({ pkgs, lib, ... }:
let

  encServices = [
    {
      address = "sensu.gocept.net";
      location = "test";
      password = "uiae";
      service = "sensuserver-server";
    }
    {
      address = "sensu.gocept.net";
      location = "test";
      password = "uiae";
      service = "sensuserver-api";
    }
  ];

  encServiceClients = [
    {
      location = "test";
      node = "client.gocept.net";
      password = "uiae";
      service = "sensuserver-server";
    }
    {
      location = "test";
      node = "sensu.gocept.net";
      password = "uiae";
      service = "sensuserver-server";
    }
  ];

  net4Srv = "10.0.1";
  net6Srv = "2001:db8:1::";

  client4Srv = net4Srv + ".1";
  client6Srv = net6Srv + "1";

  server4Srv = net4Srv + ".2";
  server6Srv = net6Srv + "2";

  net4Fe = "10.0.2";
  net6Fe = "2001:db8:2::";
  server4Fe = net4Fe + ".2";
  server6Fe = net6Fe + "2";

  hosts = ''
    127.0.0.1 localhost
    ::1 localhost
    ${server4Fe} sensu.test.gocept.net
    ${server6Fe} sensu.test.gocept.net
    ${server4Srv} sensu.gocept.net sensu
    ${server6Srv} sensu.gocept.net sensu
  '';

in {
  name = "sensuserver";

  nodes = {

    client =
      { pkgs, config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        environment.etc.hosts.source = lib.mkForce (pkgs.writeText "hosts" hosts);
        flyingcircus.encServices = encServices;
        flyingcircus.encServiceClients = encServiceClients;
        flyingcircus.services.sensu-client.enable = true;

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:01:01";
            bridged = false;
            networks = {
              "${net4Srv}.0/24" = [ client4Srv ];
              "${net6Srv}/64" = [ client6Srv ];
            };
            gateways = {};
          };
        };

        virtualisation.vlans = [ 1 ];
      };

    sensu =
      { pkgs, config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        environment.etc.hosts.source = lib.mkForce (pkgs.writeText "hosts" hosts);
        flyingcircus.encServices = encServices;
        flyingcircus.encServiceClients = encServiceClients;
        flyingcircus.roles.sensuserver.enable = true;
        flyingcircus.services.sensu-client.enable = true;

        systemd.services."acme-sensu.test.gocept.net.service" = lib.mkForce {};

        flyingcircus.enc.parameters.location = "test";

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:01:02";
            bridged = false;
            networks = {
              "${net4Srv}.0/24" = [ server4Srv ];
              "${net6Srv}/64" = [ server6Srv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:02";
            bridged = false;
            networks = {
              "${net4Fe}.0/24" = [ server4Fe ];
              "${net6Fe}/64" = [ server6Fe ];
            };
            gateways = {};
          };
        };

        networking.domain = "gocept.net";

        users.groups = {
          sudo-srv = {
            members = [ "test" ];
          };
        };

        users.users = {
          test = {
            isNormalUser = true;
            hashedPassword = "$5$YF.qhP4xh$N.hX/1SMxmjqjYZqmrtTClzzSLOR/scz.TTmz4KAFX2";
          };
        };

        virtualisation.diskSize = 1000;
        virtualisation.memorySize = 2000;
        virtualisation.vlans = [ 1 2 ];
      };

  };

  testScript = let
    amqpPortCheck = "nc -z ${server4Srv} 5672";
    api = path: "curl -vfu sensuserver-api:uiae 127.0.0.1:4567${path}";
  in ''
    start_all()
    sensu.wait_for_unit("rabbitmq.service")
    sensu.wait_until_succeeds("${amqpPortCheck}")
    sensu.wait_for_unit("sensu-server")
    sensu.wait_for_unit("sensu-api")
    sensu.wait_for_unit("uchiwa")

    with subtest("uchiwa frontend should respond"):
      sensu.wait_until_succeeds("curl -vfk https://sensu.test.gocept.net/")

    with subtest("uchiwa config should have an entry for the test user"):
      sensu.succeed("uchiwa-show-config | jq -e '.uchiwa.users[0].username == \"test\"'")

    with subtest("sensu server should be healthy"):
      sensu.wait_until_succeeds("${api "/health"}")

    with subtest("sensu server should have registered the client"):
      sensu.wait_until_succeeds("${api "/clients/client"}")

    with subtest("sensu server should have its own results"):
      # jq accesses the first element in the resulting list and returns 0 if it's present, else 1.
      sensu.wait_until_succeeds("${api "/results/sensu"} | jq -e '.[0]'")

    with subtest("sensu server should have results for the client"):
      sensu.wait_until_succeeds("${api "/results/client"} | jq -e '.[0]'")
  '';
})
