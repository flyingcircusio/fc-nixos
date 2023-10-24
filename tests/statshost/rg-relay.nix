import ../make-test-python.nix ({ pkgs, testlib, ... }:
let
  inherit (testlib) fcConfig fcIP;
in
{
  name = "rg-relay";
  nodes = {
    relay = {
      imports = [ (fcConfig { id = 1; }) ];

      flyingcircus.roles.statshost-relay.enable = true;
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

      networking.firewall.allowedTCPPorts = [ 9090 ];
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

      networking.firewall.allowedTCPPorts = [ 9126 ];
    };

    statshost = {
      imports = [ (fcConfig { id = 3; }) ];

      environment.systemPackages = [ pkgs.curl ];
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

    with subtest("scrapeconfig.json from relay should return config"):
      statshost.wait_until_succeeds('curl -sSf relay:9090/scrapeconfig.json')
      statshost.succeed('curl relay:9090/scrapeconfig.json | grep -q statsSource:9126')

    with subtest("proxied request through relay should return metrics from statsSource"):
      statshost.succeed('curl -x relay:9090 statsSource:9126/metrics | grep system_uptime')

    with subtest("nginx access log file should show metrics request"):
      relay.succeed('grep "metrics" /var/log/nginx/statshost-relay_access.log')

    with subtest("nginx only opens expected ports"):
      # Look for ports that are not 81 (nginx status page port) or 9090.
      relay.fail("netstat -tlpn | grep nginx | egrep -v ':81 |:9090 '")

    with subtest("logrotate should work"):
      relay.execute("echo test > /var/log/nginx/statshost-relay_error.log")
      relay.succeed("fc-logrotate -f")
      relay.succeed("stat /var/log/nginx/statshost-relay_access.log-*")
      relay.succeed("stat /var/log/nginx/statshost-relay_error.log-*")
  '';
})
