import ../make-test-python.nix ({ pkgs, ... }:
{
  name = "rg-relay";
  nodes = {
    relay = {
      imports = [ ../../nixos ../../nixos/roles ];
      flyingcircus.roles.statshost-relay.enable = true;
      networking.nameservers = [ "127.0.0.53" ];
      services.resolved.enable = true;
      networking.firewall.allowedTCPPorts = [ 9090 ];
      environment.etc."local/statshost/scrape-rg.json".text = ''
        [
          {"targets":["statsSource:9126"]}
        ]
      '';

      services.telegraf.enable = false;

    };

    statsSource = {
      imports = [ ../../nixos ../../nixos/roles ];
      networking.firewall.allowedTCPPorts = [ 9126 ];
      services.telegraf.enable = false;
    };

    statshost = {
      imports = [ ../../nixos ../../nixos/roles ];
      environment.systemPackages = [ pkgs.curl ];
      services.telegraf.enable = false;
    };
  };

  testScript = ''
    start_all()
    statsSource.execute("""
      echo 'system_uptime' > metrics
      ${pkgs.python3.interpreter} -m http.server 9126 >&2 &
    """)

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
