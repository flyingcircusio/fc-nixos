import ./make-test-python.nix (
  {
    testlib,
    pkgs,
    ...
  }:
  let
    loki_collector_v4 = testlib.fcIP.srv4 1;
    loki_collector_v6 = testlib.fcIP.srv6 1;
    loki_relay_v4 = testlib.fcIP.srv4 2;
    loki_relay_v6 = testlib.fcIP.srv6 2;
  in
  {
    name = "loki-relay";

    nodes = {
      loki_collector =
        {
          lib,
          pkgs,
          ...
        }:
        {
          imports = [
            ../nixos
            ../nixos/roles
            (testlib.fcConfig {
              id = 1;
              net.fe = false;
              resource_group = "test2";
            })
          ];

          flyingcircus = {
            roles.loki = {
              enable = true;
              storageSchedule.default = lib.mkForce [
                {
                  startDate = "2024-09-10";
                  backend = "filesystem";
                }
              ];
            };
            enc.role_configuration."statshost-master".relay_from_details = {
              loki_relay.addresses = [
                loki_relay_v4
                loki_relay_v6
              ];
            };
          };

          environment.variables.LOKI_ADDR = "http://127.0.0.1:3100";
          environment.systemPackages = [ pkgs.grafana-loki ];
        };

      loki_relay =
        {
          lib,
          pkgs,
          ...
        }:
        {
          imports = [
            ../nixos
            ../nixos/roles
            (testlib.fcConfig {
              id = 2;
              net.fe = false;
              resource_group = "test";
            })
          ];
          networking.firewall.enable = false;

          flyingcircus.roles.loki-relay.enable = true;
          flyingcircus.enc.role_configuration."statshost-relay" = {
            relay_to = [ "loki_collector" ];
            relay_to_details = {
              loki_collector.addresses = [
                loki_collector_v4
                loki_collector_v6
              ];
            };
          };
        };

      testvm =
        { lib, pkgs, ... }:
        {
          imports = [
            ../nixos
            ../nixos/roles
            (testlib.fcConfig {
              id = 3;
              net.fe = false;
              resource_group = "test";
            })
          ];

          flyingcircus.encServices = [
            {
              address = "loki_relay";
              service = "loki-collector";
              ips = [
                loki_relay_v4
                loki_relay_v6
              ];
            }
          ];

          # test service to spam something easily greppable into syslog
          systemd.services.testservice = {
            enable = true;
            wantedBy = [ "multi-user.target" ];
            after = [
              "network.target"
              "alloy.service"
            ];

            serviceConfig.ExecStart = pkgs.writeShellScript "testservice.sh" ''
              while true; do
                echo "test message"
                sleep 1
              done
            '';
          };
        };
    };

    testScript =
      { nodes, ... }:
      let
        testscript = pkgs.writeShellScript "test-syslog-in-loki.sh" ''
          test $(logcli -q query '{systemd_unit="testservice.service"} |= `test message`' | wc -l) -gt 0
        '';
      in
      ''
        loki_collector.wait_for_unit("loki.service")
        loki_collector.wait_for_unit("nginx.service")

        loki_collector.wait_for_unit("network.target")
        loki_relay.wait_for_unit("network.target")
        testvm.wait_for_unit("network.target")

        testvm.wait_for_unit("testservice.service")

        loki_relay.sleep(5)
        loki_collector.sleep(5)
        testvm.sleep(5)

        testvm.succeed("curl http://loki_relay:3100")
        loki_relay.succeed("curl http://loki_collector:3100")
        loki_collector.succeed('${testscript}')
      '';
  }
)
