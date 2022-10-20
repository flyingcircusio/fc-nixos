import ../make-test-python.nix ({ pkgs, lib, ... }:
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
      environment.etc.hosts.source = lib.mkForce (pkgs.writeText "hosts" hosts);

      flyingcircus.enc.parameters = {
        location = "remote";
        resource_group = "test";
        interfaces.fe = {
          mac = "52:54:00:12:02:01";
          bridged = false;
          networks = {
            "${net4Fe}.0/24" = [ proxy4Fe ];
            "${net6Fe}/64" = [ proxy6Fe ];
          };
          gateways = {};
        };
        interfaces.srv = {
          mac = "52:54:00:12:01:01";
          bridged = false;
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
          location = "loc";
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:01:02";
            bridged = false;
            networks = {
              "${netLoc4Srv}.0/24" = [ statshost4Srv ];
              "${netLoc6Srv}/64" = [ statshost6Srv ];
            };
            gateways = {};
          };
          interfaces.fe = {
            mac = "52:54:00:12:02:02";
            bridged = false;
            networks = {
              "${net4Fe}.0/24" = [ statshost4Fe ];
              "${net6Fe}/64" = [ statshost6Fe ];
            };
            gateways = {};
          };
        };

        flyingcircus.encServices = encServices;

        environment.etc.hosts.source = lib.mkForce (pkgs.writeText "hosts" hosts);
        networking.domain = "fcio.net";

        services.telegraf.enable = true;  # set in infra/fc but not in infra/testing

        flyingcircus.roles.statshost.prometheusLocationProxyExtraSettings = {
          # We are talking to a fake stats source that only speaks HTTP/1.1
          # using python http.server. Without this, prometheus only tries HTTP/2
          # and fails.
          enable_http2 = false;
          tls_config = { ca_file = "/proxy_cert.pem"; };
        };

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
        location = "remote";
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:01:03";
          bridged = false;
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
    statssource.execute("""
      echo 'system_test 42' > metrics
      echo 'org_graylog2_test 42' >> metrics
      echo 'not_allowed_globally 42' >> metrics
      ${pkgs.python3.interpreter} -m http.server 9126 >&2 &
    """)

    proxy.wait_for_unit("nginx.service")
    proxy.execute("systemctl stop acme-proxy.fe.remote.fcio.net.service")
    _, cert = proxy.execute("cat /var/lib/acme/proxy.fe.remote.fcio.net/chain.pem")
    statshost.execute(f"echo '{cert}' > /proxy_cert.pem")
    statshost.execute("systemctl restart prometheus")

    statshost.execute("systemctl stop acme-statshost.fe.loc.fcio.net.service")
    statshost.wait_for_unit("prometheus.service")
    statshost.wait_for_unit("influxdb.service")
    statshost.wait_for_unit("grafana.service")

    statssource.wait_for_open_port(9126)

    with subtest("request through location proxy should return metrics (HTTP)"):
      statshost.succeed('curl -x http://${proxyFe}:9090 ${statssourceSrv}:9126/metrics | grep -q system_test')

    with subtest("nginx access log file should show metrics request"):
      proxy.succeed('grep "metrics" /var/log/nginx/statshost-location-proxy_access.log')

    with subtest("request through location proxy should return metrics (HTTPS)"):
      statshost.succeed('SSL_CERT_FILE=/proxy_cert.pem curl -x https://${proxyFe}:9443 ${statssourceSrv}:9126/metrics | grep -q system_test')

    check_remote_target = """
      curl -s ${api}/targets | jq -e '.data.activeTargets[] | select(.health == "up" and .labels.job == "remote")'
    """

    with subtest("Prometheus job for RG remote should be configured and up"):
      statshost.succeed('stat /etc/current-config/statshost-relay-remote.json')
      statshost.wait_until_succeeds(check_remote_target)

    with subtest("prometheus should ingest metric from statssource"):
      statshost.wait_until_succeeds("curl -s ${api}/query?query=system_test | jq -e '.data.result[].value[1] == \"42\"'")

    with subtest("prometheus should keep renamed metric for graylog"):
      statshost.succeed("curl -s ${api}/query?query=graylog_test | jq -e '.data.result[].value[1] == \"42\"'")

    with subtest("prometheus should drop metric that is not allowed globally"):
      statshost.fail("curl -s ${api}/query?query=not_allowed_globally | jq -e '.data.result[].value[1] == \"42\"'")

    with subtest("nginx only opens expected ports"):
      # look for ports that are not 80 (nginx default for status info) 9090 (metrics HTTP), 9443 (metrics HTTPS)
      proxy.fail("netstat -tlpn | grep nginx | egrep -v ':80 |:9090 |:9443 '")
  '';
})
