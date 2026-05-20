import ../make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    inherit (testlib) fcConfig fcIP;

    relay_v4 = fcIP.srv4 1;
    relay_v6 = fcIP.srv6 1;
    stats_host_v4 = fcIP.srv4 3;
    stats_host_v6 = fcIP.srv6 3;
  in
  {
    name = "rg-relay";
    nodes = {
      relay = {
        imports = [ (fcConfig { id = 1; }) ];

        flyingcircus.roles.statshost-relay.enable = true;

        networking.firewall.enable = false;

        flyingcircus.enc.role_configuration."statshost-relay" = {
          relay_to_details.statshost.addresses = [
            stats_host_v4
            stats_host_v6
          ];
        };

        environment.etc."local/statshost/scrape-rg.json".text = ''
          [
            {"targets":["statsSource:9126"]}
          ]
        '';
        # IPv4 is included by default but Nginx also wants to
        # resolve IPv6. Without it, Nginx just returns 502 on proxy requests.
        networking.extraHosts = ''
          ${fcIP.srv6 2} statsSource
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

      statsSource = {
        imports = [ (fcConfig { id = 2; }) ];
        networking.firewall.enable = false;
      };

      statshost = {
        imports = [ (fcConfig { id = 3; }) ];
        environment.systemPackages = [ pkgs.curl ];

        flyingcircus.enc.role_configuration."statshost-relay" = {
          relay_from_details.relay.addresses = [
            relay_v4
            relay_v6
          ];
        };
      };
    };

    testScript = ''
      start_all()
      statsSource.execute("""
        echo 'system_uptime' > metrics
        python -m http.server 9126 >&2 &
      """)
      statsSource.wait_for_open_port(9126)

      relay.wait_for_unit("nginx.service")
      relay.wait_for_open_port(9090)

      print("statshost")
      print(statshost.execute("ip -4 a")[1])
      print(statshost.execute("ping -c 3 relay")[1])

      print("relay")
      print(relay.execute("ip -4 a")[1])

      with subtest("scrapeconfig.json from relay should return config"):
        statshost.wait_until_succeeds('curl -sSf relay:9090/scrapeconfig.json')
        statshost.succeed('curl relay:9090/scrapeconfig.json | grep -q statsSource:9126')

      with subtest("proxied request through relay should return metrics from statsSource"):
        statshost.succeed('curl -x relay:9090 statsSource:9126/metrics | grep system_uptime')

      with subtest("nginx access log file should show metrics request"):
        relay.succeed('grep "metrics" /var/log/nginx/statshost-relay_access.log')

      with subtest("nginx only opens expected ports"):
        # Look for ports that are not 81 (nginx status page port) or 9090.
        relay.fail("ss -tlpn | grep nginx | egrep -v ':81 |:9090 '")

      with subtest("logrotate should work"):
        relay.execute("echo test > /var/log/nginx/statshost-relay_error.log")
        relay.succeed("fc-logrotate -f")
        relay.succeed("stat /var/log/nginx/statshost-relay_access.log-*")
        relay.succeed("stat /var/log/nginx/statshost-relay_error.log-*")
    '';
  }
)
