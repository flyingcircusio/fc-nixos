import ../make-test-python.nix (
  {
    pkgs,
    testlib,
    lib,
    ...
  }:
  let
    inherit (testlib) fcConfig fcIP;

    stats_source_v4 = fcIP.srv4 1;
    stats_source_v6 = fcIP.srv6 1;
    relay_v4 = fcIP.srv4 2;
    relay_v6 = fcIP.srv6 2;
    stats_host_v4 = fcIP.srv4 3;
    stats_host_v6 = fcIP.srv6 3;
  in
  {
    name = "rg-relay";
    nodes = {
      statsSource = {
        imports = [
          (fcConfig {
            id = 1;
            resource_group = "test1";
          })
        ];

        services.nginx = {
          enable = true;

          virtualHosts."test" = {
            default = true;
            listen = [
              {
                addr = stats_source_v4;
                port = 9126;
              }
            ];
            locations."= /metrics" = {
              return = ''
                200 'system_uptime{host="statsSource",platform="nixos",resource_group="test1"} 42'
              '';
              extraConfig = ''
                default_type text/plain;
              '';
            };
          };
        };

        networking.firewall.enable = false;
      };

      relay = { lib, ... }: {
        imports = [
          (fcConfig {
            id = 2;
            resource_group = "test1";
          })
        ];

        flyingcircus.roles.statshost-relay.enable = true;

        networking.firewall.enable = false;

        flyingcircus.enc.role_configuration."statshost-relay" = {
          relay_to_details.statshost.addresses = [
            stats_host_v4
            stats_host_v6
          ];
        };

        environment.etc."local/statshost/scrape-rg.json".text = lib.mkForce ''
          [{"targets": ["${stats_source_v4}:9126"]}]
        '';

        # IPv4 is included by default but Nginx also wants to
        # resolve IPv6. Without it, Nginx just returns 502 on proxy requests.
        networking.extraHosts = ''
          ${stats_source_v4} statsSource
          ${stats_source_v6} statsSource
        '';

        # Nginx wants to talk to DNS, so we set up a dnsmasq that serves /etc/hosts.
        services.dnsmasq = {
          enable = true;
          settings = {
            log-queries = true;
            resolv-file = "/etc/hosts";
          };
        };
      };

      statshost = { config, lib, ... }: {
        imports = [
          (fcConfig {
            id = 3;
            resource_group = "test2";
          })
        ];
        environment.systemPackages = [ pkgs.curl ];
        networking.firewall.enable = false;

        flyingcircus.roles.statshost.enable = true;
        flyingcircus.roles.statshost.useSSL = false;
        flyingcircus.roles.statshost-master.enable = true;
        # enable statshost role for prometheus only, no need for nginx or grafana
        services.grafana.enable = lib.mkForce false;
        services.nginx.enable = lib.mkForce false;
        flyingcircus.services.nginx.enable = lib.mkForce false;
        systemd.services.fc-grafana-load-dashboards.enable = false;

        flyingcircus.enc.role_configuration."statshost-master" = {
          relay_from_details.relay.addresses = [
            relay_v6
            relay_v4
          ];
        };
      };
    };

    testScript = ''
      start_all()
      statsSource.wait_for_open_port(9126, "${stats_source_v4}")
      relay.wait_for_unit("nginx.service")
      relay.wait_for_open_port(9090)

      with subtest("scrapeconfig.json from relay should return config"):
        statshost.wait_until_succeeds('curl -sSf relay:9090/scrapeconfig.json')
        statshost.succeed('curl relay:9090/scrapeconfig.json | grep -q ${stats_source_v4}:9126')

      with subtest("proxied request through relay should return metrics from statsSource"):
        statshost.succeed('curl -x relay:9090 statsSource:9126/metrics | grep system_uptime')

      with subtest("nginx access log file should show metrics request"):
        relay.succeed('grep "metrics" /var/log/nginx/statshost-relay_access.log')

      with subtest("nginx only opens expected ports"):
        # Look for ports that are not 81 (nginx status page port) or 9090.
        relay.fail("ss -tlpn | grep nginx | egrep -v ':81 |:9090 '")

      statshost.systemctl("start fc-prometheus-update-relayed-nodes")

      statshost.systemctl("restart prometheus")
      statshost.wait_for_unit("prometheus.service")
      statshost.wait_for_open_port(9090, "${stats_host_v4}")
      statshost.wait_until_succeeds("""
         curl -s http://${stats_host_v4}:9090/api/v1/query?query='system_uptime' | \
         ${pkgs.jq}/bin/jq -e '.data.result[].value[1] == "42"'
         """)

      with subtest("logrotate should work"):
        relay.execute("echo test > /var/log/nginx/statshost-relay_error.log")
        relay.succeed("fc-logrotate -f")
        relay.succeed("stat /var/log/nginx/statshost-relay_access.log-*")
        relay.succeed("stat /var/log/nginx/statshost-relay_error.log-*")
    '';
  }
)
