import ./make-test.nix ({ pkgs, ... }:
{
  name = "rg-relay";
  nodes = {
    relay = {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.statshost-relay.enable = true;
      networking.nameservers = [ "127.0.0.53" ];
      services.resolved.enable = true;
      networking.firewall.allowedTCPPorts = [ 9090 ];
      environment.etc."local/statshost/scrape-rg.json".text = ''
        [
          {"targets":["statsSource:9126"]}
        ]
      '';
    };

    statsSource = {
      imports = [ ../nixos ];
      networking.firewall.allowedTCPPorts = [ 9126 ];
    };

    statshost = {
      imports = [ ../nixos ];
      environment.systemPackages = [ pkgs.curl ];
    };
  };

  testScript = ''
    startAll;
    $statsSource->execute(<<__SETUP__);
    echo 'system_uptime' > metrics
    ${pkgs.python3.interpreter} -m http.server 9126 &
    __SETUP__

    $relay->waitForUnit("nginx.service");
    $relay->waitForOpenPort(9090);

    subtest "scrapeconfig.json from relay should return config", sub {
      $statshost->succeed('curl relay:9090/scrapeconfig.json | grep -q statsSource:9126');
    };

    subtest "proxied request through relay should return metrics from statsSource", sub {
      $statshost->succeed('curl -x relay:9090 statsSource:9126/metrics | grep -q system_uptime');
    };

    subtest "nginx access log file should show metrics request", sub {
      $relay->succeed('grep "metrics" /var/log/nginx/statshost-relay_access.log');
    };

    subtest "nginx only opens expected ports", sub {
      # look for ports that are not 80 (nginx default for status info) or 9090
      $relay->mustFail("netstat -tlpn | grep nginx | egrep -v ':80 |:9090 '");
    }
  '';
})
