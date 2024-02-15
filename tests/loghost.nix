import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:
let
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
  host = "machine.fcio.net";
in {
  name = "loghost";
  machine =
    { config, ... }:
    {
      imports = [
        ../nixos
        ../nixos/roles
      ];

      environment.systemPackages = [ pkgs.tcpdump ];

      virtualisation.memorySize = 6000;
      virtualisation.qemu.options = [ "-smp 2" ];

      flyingcircus.roles.loghost.enable = true;
      networking.domain = "fcio.net";

      services.telegraf.enable = true;  # set in infra/fc but not in infra/testing

      flyingcircus.roles.elasticsearch.heapPercentage = 30;
      flyingcircus.services.graylog.heapPercentage = 35;

      flyingcircus.enc.parameters = {
        directory_password = "asdf";
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:02:01";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:01:01";
          bridged = false;
          networks = {
            "10.0.0.0/24" = [ "10.0.0.3" ];
            "2001:db8:3::/64" = [ "2001:db8:3::3" ];
          };
          gateways = {};
        };
      };

      virtualisation.vlans = [ 1 2 ];

      users.groups.login = {
        members = [];
      };

      flyingcircus.encServices = [
        { service = "loghost-server";
          address = host;
          ips = [ ipv4 ipv6 ];
        }
      ];
      environment.etc.hosts.source = lib.mkForce (pkgs.writeText "hosts" ''
        ${ipv4} ${host}
        ${ipv6} ${host}
      '');

      flyingcircus.roles.graylog.publicFrontend = {
        enable = true;
        hostName = host;
      };
      flyingcircus.allowedUnfreePackageNames = [ "mongodb" ];

    };

  testScript = { nodes, ... }:
  let
    config = nodes.machine.config;
    sensuChecks = config.flyingcircus.services.sensu-client.checks;
    graylogCheck = testlib.sensuCheckCmd nodes.machine "graylog_ui";
    graylogApi = "${pkgs.fc.agent}/bin/fc-graylog --api http://${host}:9001/api get -l";
    esConfigFile = "/srv/elasticsearch/config/elasticsearch.yml";
  in ''
    machine.wait_for_unit("elasticsearch.service")

    with subtest("elasticsearch config should be set-up for single-node mode"):
      machine.succeed("grep 'discovery.type: single-node' ${esConfigFile}")
      machine.succeed("grep 'discovery.zen.minimum_master_nodes: 1' ${esConfigFile}")

    with subtest("elasticsearch auto_create_index should be disabled"):
      machine.succeed("grep 'action.auto_create_index: false' ${esConfigFile}")

    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("mongodb.service")
    machine.wait_for_unit("graylog.service")
    machine.wait_for_unit("nginx.service")

    with subtest("elasticsearch should have a graylog index"):
      machine.wait_until_succeeds("curl http://${host}:9200/_cat/indices?v | grep -q graylog_0")

    with subtest("graylog API should respond"):
      machine.wait_until_succeeds("${graylogApi} / | grep -q cluster_id")

    with subtest("config script must create telegraf user"):
      machine.wait_for_unit("fc-graylog-config.service")
      machine.succeed("${graylogApi} /users | grep -q telegraf-machine")

    with subtest("public HTTPS should serve graylog dashboard"):
      machine.wait_until_succeeds("curl -k https://${host} | grep -q 'Graylog Web Interface'")

    with subtest("sensu check should be green"):
      machine.succeed("${graylogCheck}")

    with subtest("sensu check should be red after shutting down graylog"):
      machine.stop_job("graylog.service")
      machine.wait_until_fails("${graylogApi} / | grep -q cluster_id")
      machine.fail("${graylogCheck}")

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u graylog touch /etc/local/graylog/graylog.json')

    with subtest("secret files should have correct permissions"):
      machine.succeed("stat /etc/local/graylog/password -c %a:%U:%G | grep '660:graylog:service'")
      machine.succeed("stat /etc/local/graylog/password_secret -c %a:%U:%G | grep '660:graylog:service'")
      machine.succeed("stat /run/graylog/graylog.conf -c %a:%U:%G | grep '440:graylog:service'")
  '';
})
