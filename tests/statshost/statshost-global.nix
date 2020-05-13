import ../make-test.nix ({ pkgs, lib, ... }:
let

  netLoc4Srv = "10.0.1";
  statshost4Srv = netLoc4Srv + ".2";

  netLoc6Srv = "2001:db8:1::";
  statshost6Srv = netLoc6Srv + "2";

  netRemote4Srv = "10.0.2";
  proxy4Srv = netRemote4Srv + ".1";
  statsSource4Srv = netRemote4Srv + ".3";

  netRemote6Srv = "2001:db8:2::";
  proxy6Srv = netRemote6Srv + "1";
  statsSource6Srv = netRemote6Srv + "3";

  net4Fe = "10.0.3";
  proxy4Fe = net4Fe + ".1";
  statshost4Fe = net4Fe + ".2";

  net6Fe = "2001:db8:3::";
  proxy6Fe = net6Fe + "1";
  statshost6Fe = net6Fe + "2";

  proxySrv = "proxy.fcio.net";
  statshostSrv = "statshost.fcio.net";
  statssourceSrv = "statssource.fcio.net";

  proxyFe = "proxy.fe.remote.fcio.net";
  statshostFe = "statshost.fe.loc.fcio.net";

  hosts = ''
    127.0.0.1 localhost
    ::1 localhost

    ${proxy6Srv} ${proxySrv}
    ${proxy6Fe} ${proxyFe}
    ${statshost6Srv} ${statshostSrv}
    ${statshost6Fe} ${statshostFe}
    ${statsSource6Srv} ${statssourceSrv}

    ${proxy4Srv} ${proxySrv}
    ${proxy4Fe} ${proxyFe}
    ${statshost4Srv} ${statshostSrv}
    ${statshost4Fe} ${statshostFe}
    ${statsSource4Srv} ${statssourceSrv}
  '';

  encServiceClients = [
    {
      node = statssourceSrv;
      service = "statshost-collector";
      location = "remote";
    }
  ];

  encServices = [
    {
      ips = [
        proxy4Fe
        proxy6Fe
      ];
      address = proxySrv;
      service = "statshostproxy-location";
      location = "remote";
    }
    {
      ips = [
        statshost4Fe
        statshost6Fe
      ];
      address = statshostSrv;
      service = "statshost-collector";
      location = "loc";
    }

  ];

in {
  name = "statshost";
  nodes = {
    proxy = {
      imports = [ ../../nixos ../../nixos/roles ];
      flyingcircus.roles.statshost-location-proxy.enable = true;
      flyingcircus.roles.statshost.hostName = statshostFe;
      flyingcircus.encServices = encServices;
      networking.nameservers = [ "127.0.0.53" ];
      networking.domain = "fcio.net";
      services.resolved.enable = true;
      # Overwrite auto-generated entries for the 192.168.* net.
      environment.etc.hosts.text = lib.mkForce hosts;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.fe = {
          mac = "52:54:00:12:02:01";
          networks = {
            "${net4Fe}.0/24" = [ proxy4Fe ];
            "${net6Fe}/64" = [ proxy6Fe ];
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:01:01";
          networks = {
            "${netRemote4Srv}.0/24" = [ proxy4Srv ];
            "${netRemote6Srv}/64" = [ proxy6Srv ];
          };
          gateways = {};
        };
      };
      virtualisation.vlans = [ 1 2 ];
    };

    statshost =
      { config, ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];
        flyingcircus.roles.statshost-global.enable = true;
        flyingcircus.roles.statshost.hostName = statshostFe;

        flyingcircus.encServiceClients = encServiceClients;
        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:01:02";
            networks = {
              "${netLoc4Srv}.0/24" = [ statshost4Srv ];
              "${netLoc6Srv}/64" = [ statshost6Srv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:02";
            networks = {
              "${net4Fe}.0/24" = [ statshost4Fe ];
              "${net6Fe}/64" = [ statshost6Fe ];
            };
            gateways = {};
          };
        };

        flyingcircus.encServices = encServices;

        environment.etc.hosts.text = lib.mkForce hosts;
        networking.domain = "fcio.net";

        services.telegraf.enable = true;  # set in infra/fc but not in infra/testing

        users.users.s-test = {
          isNormalUser = true;
          extraGroups = [ "service" ];
        };

        virtualisation.vlans = [ 1 2 ];
        virtualisation.memorySize = 3000;
        virtualisation.diskSize = 1000;

      };

    statssource = {
      imports = [ ../../nixos ../../nixos/roles ];
      networking.firewall.allowedTCPPorts = [ 9126 ];
      environment.etc.hosts.text = lib.mkForce hosts;
      networking.domain = "fcio.net";
      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:01:03";
          networks = {
            "${netRemote4Srv}.0/24" = [ statsSource4Srv ];
            "${netRemote6Srv}/64" = [ statsSource6Srv ];
          };
          gateways = {};
        };
      };
    };

  };

  testScript = let
    api = "http://${statshostSrv}:9090/api/v1";
  in ''
    $statshost->waitForUnit("prometheus.service");
    $statshost->waitForUnit("influxdb.service");
    $statshost->waitForUnit("grafana.service");
    $statshost->waitForUnit("collectdproxy-statshost.service");

    $statssource->execute(<<__SETUP__);
    echo 'system_test 42' > metrics
    echo 'org_graylog2_test 42' >> metrics
    echo 'not_allowed_globally 42' >> metrics
    ${pkgs.python3.interpreter} -m http.server 9126 &
    __SETUP__

    $proxy->waitForUnit("nginx.service");

    subtest "request through location proxy should return metrics (HTTP)", sub {
      $statshost->succeed('curl -x http://${proxyFe}:9090 ${statssourceSrv}:9126/metrics | grep -q system_test');
    };

    subtest "nginx access log file should show metrics request", sub {
      $proxy->succeed('grep "metrics" /var/log/nginx/statshost-location-proxy_access.log');
    };

    subtest "request through location proxy should return metrics (HTTPS)", sub {
      $statshost->succeed('curl --proxy-insecure -kx https://${proxyFe}:9443 ${statssourceSrv}:9126/metrics | grep -q system_test');
    };

    my $checkRemoteTarget = <<'EOF';
      curl -s ${api}/targets | \
        jq -e \
        '.data.activeTargets[] |
          select(.health == "up" and .labels.job == "remote")'
    EOF

    subtest "Prometheus job for RG remote should be configured and up", sub {
      $statshost->succeed('stat /etc/current-config/statshost-relay-remote.json');
      $statshost->waitUntilSucceeds($checkRemoteTarget);
    };

    subtest "prometheus should ingest metric from statssource", sub {
      $statshost->waitUntilSucceeds("curl -s ${api}/query?query=system_test | jq -e '.data.result[].value[1] == \"42\"'");
    };

    subtest "prometheus should keep renamed metric for graylog", sub {
      $statshost->succeed("curl -s ${api}/query?query=graylog_test | jq -e '.data.result[].value[1] == \"42\"'");
    };

    subtest "prometheus should drop metric that is not allowed globally", sub {
      $statshost->mustFail("curl -s ${api}/query?query=not_allowed_globally | jq -e '.data.result[].value[1] == \"42\"'");
    };

    subtest "nginx only opens expected ports", sub {
      # look for ports that are not 80 (nginx default for status info) 9090 (metrics HTTP), 9443 (metrics HTTPS)
      $proxy->mustFail("netstat -tlpn | grep nginx | egrep -v ':80 |:9090 |:9443 '");
    };

    $proxy->waitForUnit("collectdproxy-location.service");

    # Generate a lot of metric lines to fill up the buffer of collectdproxy.
    # Collectdproxy only sends metrics when the buffer is full.
    $statssource->execute('seq -f "statssource 1 %03g" 800 > collectd_metrics');

    $proxy->waitUntilSucceeds("netstat -nl | grep 2003");
    $statshost->waitUntilSucceeds("netstat -nl | grep 2003");
    $statshost->waitUntilSucceeds("netstat -nl | grep 2004");

    subtest "metrics sent from statssource should appear in influx", sub {
      $statssource->succeed('nc -u -w5 ${proxy6Srv} 2003 < collectd_metrics');
      $statshost->waitUntilSucceeds('influx -database graphite -execute "show measurements" | grep -q statssource');
    };
  '';
})
