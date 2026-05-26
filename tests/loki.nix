import ./make-test-python.nix (
  {
    testlib,
    pkgs,
    ...
  }:
  {
    name = "loki";
    nodes.alloy =
      {
        lib,
        pkgs,
        ...
      }:
      {
        imports = [

          ../nixos
          ../nixos/roles
          (testlib.fcConfig { net.fe = false; })
        ];
        flyingcircus.roles.loki.enable = true;

        flyingcircus.encServices = [
          {
            address = "127.0.0.1";
            service = "loki-collector";
            ips = [
              (testlib.fcIP.srv4 1)
              (testlib.fcIP.srv6 1)
            ];
          }
        ];

        environment.variables = {
          LOKI_ADDR = "http://127.0.0.1:3100";
        };

        environment.systemPackages = [
          pkgs.grafana-loki
        ];

        # test service to spam something easily greppable into syslog
        systemd.services.testservice = {
          enable = true;
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "loki.service"
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

    testScript =
      { nodes, ... }:
      let
        testscript = pkgs.writeShellScript "test-syslog-in-loki.sh" ''
          test $(logcli -q query '{hostname="alloy", systemd_unit="testservice.service"} |= `test message`' | wc -l) -gt 0
        '';
      in
      ''
        alloy.wait_for_open_port(3100)
        alloy.wait_for_unit("testservice.service")
        alloy.sleep(1)
        alloy.succeed('${testscript}')
      '';
  }
)
