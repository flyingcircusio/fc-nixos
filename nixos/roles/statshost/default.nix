# statshost: an InfluxDB/Grafana server. Accepts incoming graphite traffic,
# stores it and renders graphs.
# TODO: don't build if more than one location relay is active in the same location.
# Having more than one breaks prometheus.
{ config, lib, pkgs, ... }:

with lib;
with builtins;

let
  fclib = config.fclib;

  localDir = "/etc/local/statshost";

  # For details, see the option description below
  cfgStats = config.flyingcircus.roles.statshost;
  cfgStatsGlobal = config.flyingcircus.roles.statshost-global;
  cfgStatsRG = config.flyingcircus.roles.statshost-master;
  cfgProxyLocation = config.flyingcircus.roles.statshost-location-proxy;
  cfgProxyRG = config.flyingcircus.roles.statshost-relay;

  promFlags = [
    "--storage.tsdb.retention.time ${toString cfgStats.prometheusRetention}d"
  ];
  prometheusListenAddress = cfgStats.prometheusListenAddress;

  # It's common to have stathost and loghost on the same node. Each should
  # use half of the memory then. A general approach for this kind of
  # multi-service would be nice.
  heapCorrection =
    if config.flyingcircus.roles.loghost.enable
    then 50
    else 100;

  customRelabelPath = "${localDir}/metric-relabel.yaml";
  customRelabelConfig = relabelConfiguration customRelabelPath;
  customRelabelJSON = filename:
    pkgs.runCommand "${baseNameOf filename}.json" {
      buildInputs = [ pkgs.remarshal ];
      preferLocalBuild = true;
    } "remarshal -if yaml -of json < ${filename} > $out";

  relabelConfiguration = filename:
    if pathExists filename
    then fromJSON (readFile (customRelabelJSON filename))
    else [];

  prometheusMetricRelabel =
    cfgStats.prometheusMetricRelabel ++ customRelabelConfig;

  relayRGNodes =
    fclib.jsonFromFile "${localDir}/relays.json" "[]";

  relayLocationNodes = map
    (proxy: { job_name = proxy.location;
              proxy_url = "https://${proxy.address}:9443";
            } // cfgStats.prometheusLocationProxyExtraSettings)
    relayLocationProxies;

  relayLocationProxies =
    # We need the FE address, which is not published by directory. I'd think
    # "interface" should become an attribute in the services table.
    let
      makeFE = s:
        let
          proxyHostname = removeSuffix ".fcio.net" (removeSuffix ".gocept.net" s.address);
        in "${proxyHostname}.fe.${s.location}.fcio.net";
    in map
      (service: service // { address = makeFE service; })
      (filter
        (s: s.service == "statshostproxy-location")
        config.flyingcircus.encServices);

  buildRelayConfig = relayNodes: nodeConfig: map
    (relayNode: {
        scrape_interval = "15s";
        file_sd_configs = [
          {
            files = [ (nodeConfig relayNode)];
            refresh_interval = "10m";
          }
        ];
        metric_relabel_configs =
          prometheusMetricRelabel ++
          (relabelConfiguration "${localDir}/metric-relabel.${relayNode.job_name}.yaml");
      } // relayNode)
      relayNodes;

  relayRGConfig = buildRelayConfig
    relayRGNodes
    (relayNode: "/var/cache/statshost-relay-${relayNode.job_name}.json");

  relayLocationConfig = buildRelayConfig
    relayLocationNodes
    (relayNode: "/etc/current-config/statshost-relay-${relayNode.job_name}.json");

  statshostService = findFirst
    (s: s.service == "statshost-collector")
    null
    config.flyingcircus.encServices;

  grafanaLdapConfig = pkgs.writeText "ldap.toml" ''
    verbose_logging = true

    [[servers]]
    host = "ldap.fcio.net"
    port = 636
    start_tls = false
    use_ssl = true
    bind_dn = "uid=%s,ou=People,dc=gocept,dc=com"
    search_base_dns = ["ou=People,dc=gocept,dc=com"]
    search_filter = "(&(&(objectClass=inetOrgPerson)(uid=%s))(memberOf=cn=${config.flyingcircus.enc.parameters.resource_group},ou=GroupOfNames,dc=gocept,dc=com))"
    group_search_base_dns = ["ou=Group,dc=gocept,dc=com"]
    group_search_filter = "(&(objectClass=posixGroup)(memberUid=%s))"

    [servers.attributes]
    name = "cn"
    surname = "displaname"
    username = "uid"
    member_of = "cn"
    email = "mail"

    [[servers.group_mappings]]
    group_dn = "${config.flyingcircus.enc.parameters.resource_group}"
    org_role = "Admin"

  '';
  grafanaJsonDashboardPath = "${config.services.grafana.dataDir}/dashboards";
  grafanaProvisioningPath = "${config.services.grafana.dataDir}/provisioning";

in
{

  imports = [
    ./global-metrics.nix
    ./location-proxy.nix
    ./relabel.nix
    ./rg-relay.nix
  ];

  options = {


    # Options that are used by RG and the global statshost.
    flyingcircus.roles.statshost = {

      supportsContainers = fclib.mkDisableContainerSupport;

      hostName = mkOption {
        default = fclib.fqdn { vlan = "fe"; };
        type = types.str;
        description = ''
          Host name for the Grafana frontend.
          A Letsencrypt certificate is generated for it.
          Defaults to the FE FQDN.
          Also used by collectdproxy if it's the global FCIO statshost.
        '';
        example = "stats.example.com";
      };

      useSSL = mkOption {
        type = types.bool;
        description = "Whether to require HTTPS for Grafana dashboard access.";
        default = true;
      };

      prometheusMetricRelabel = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Prometheus metric relabel configuration.";
      };

      prometheusLocationProxyExtraSettings = mkOption {
        type = types.attrs;
        default = {};
        description = "Additional settings for jobs fetching from location proxies.";
        example = ''
        {
          tls_config = {
            ca_file = "/srv/prometheus/proxy_cert.pem";
          };
        }
        '';
      };

      dashboardsRepository = mkOption {
        type = types.str;
        default = "https://github.com/flyingcircusio/grafana.git";
        description = "Dashboard git repository.";
      };

      prometheusListenAddress = mkOption {
        type = types.str;
        default = "${head fclib.network.srv.dualstack.addressesQuoted}:9090";
        description = "Prometheus listen address";
      };

      prometheusRetention = mkOption {
        type = types.int;
        default = 70;
        description = "How long to keep data in *days*.";
      };

      influxdbRetention = mkOption {
        type = types.str;
        default = "inf";
        description = "How long to keep data (influx duration)";
      };

    };

    # FC infrastructure global stats host
    flyingcircus.roles.statshost-global = {

      enable = mkEnableOption "Grafana/InfluxDB stats host (global)";
      supportsContainers = fclib.mkDisableContainerSupport;

      allowedMetricPrefixes = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of globally allowed metric prefixes. Metrics not matching the
          prefix will be dropped on the *central* prometheus. This is useful
          to avoid indexing customer metrics, which have no meaning for us
          anyway.
        '';
      };

    };
    # Relays stats from an entire location to the global stats host.
    flyingcircus.roles.statshost-location-proxy = {
      enable = mkEnableOption "Stats proxy, which relays an entire location";
      supportsContainers = fclib.mkDisableContainerSupport;
    };

    # The following two roles are "customer" roles, customers can use them to
    # have their own statshost.
    flyingcircus.roles.statshost-master = {
      enable = mkEnableOption "Grafana/Prometheus stats host for one RG";
      supportsContainers = fclib.mkDisableContainerSupport;
    };

    flyingcircus.roles.statshost-relay = {
      enable = mkEnableOption "RG-specific Grafana/Prometheus stats relay";
      supportsContainers = fclib.mkDisableContainerSupport;
    };

  };

  config = mkMerge [

    # Global stats host. Currently influxdb *and* prometheus
    (mkIf cfgStatsGlobal.enable {

      services.influxdb.extraConfig = {
        graphite = [
          { enabled = true;
            protocol = "udp";
            udp-read-buffer = 8388608;
            templates = [
              # new hierarchy
              "fcio.*.*.*.*.*.ceph .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.cpu  .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.load .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.netlink .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.entropy .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.swap .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.uptime .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.processes .location.resourcegroup.machine.profile.host.measurement.field*"
              "fcio.*.*.*.*.*.users .location.resourcegroup.machine.profile.host.measurement.field"
              "fcio.*.*.*.*.*.vmem .location.resourcegroup.machine.profile.host.measurement..field"
              "fcio.*.*.*.*.*.disk .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.interface .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.postgresql .location.resourcegroup.machine.profile.host.measurement.instance.field*"
              "fcio.*.*.*.*.*.*.memory .location.resourcegroup.machine.profile.host.measurement..field*"
              "fcio.*.*.*.*.*.curl_json.*.*.* .location.resourcegroup.machine.profile.host..measurement..field*"
              "fcio.*.*.*.*.*.df.*.df_complex.* .location.resourcegroup.machine.profile.host.measurement.instance..field"
              "fcio.*.*.*.*.*.conntrack.* .location.resourcegroup.machine.profile.host.measurement.field*"
              "fcio.*.*.*.*.*.tail.* .location.resourcegroup.machine.profile.host..measurement.field*"

              # Generic collectd plugin: measurement/instance/field (i.e. load/loadl/longtermn)
              "fcio.* .location.resourcegroup.machine.profile.host.measurement.field*"

              # old hierarchy
              "fcio.*.*.*.ceph .location.resourcegroup.host.measurement.instance..field"
              "fcio.*.*.*.cpu  .location.resourcegroup.host.measurement.instance..field"
              "fcio.*.*.*.load .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.netlink .location.resourcegroup.host.measurement.instance.field*"
              "fcio.*.*.*.entropy .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.swap .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.uptime .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.processes .location.resourcegroup.host.measurement.field*"
              "fcio.*.*.*.users .location.resourcegroup.host.measurement.field"
              "fcio.*.*.*.vmem .location.resourcegroup.host.measurement..field"
              "fcio.*.*.*.disk .location.resourcegroup.host.measurement.instance.field*"
              "fcio.*.*.*.interface .location.resourcegroup.host.measurement.instance.field*"
            ];
          }
        ];
      };

      boot.kernel.sysctl."net.core.rmem_max" = mkOverride 90 25165824;

      flyingcircus.services.collectdproxy.statshost = {
        enable = true;
        sendTo = "${cfgStats.hostName}:2003";
      };

      # Global prometheus configuration
      environment.etc = listToAttrs
        (map
          (p: nameValuePair "current-config/statshost-relay-${p.location}.json"  {
            text = toJSON [
              { targets = (map
                (s: "${s.node}:9126")
                (filter
                  (s: s.service == "statshost-collector" && s.location == p.location)
                  config.flyingcircus.encServiceClients));
              }];
          })
        relayLocationProxies);
    })

    (mkIf (cfgStatsRG.enable || cfgProxyRG.enable) {
      environment.etc."local/statshost/scrape-rg.json".text = toJSON [{
        targets = sort lessThan (unique
          (map
            (host: "${host.name}.fcio.net:9126")
            config.flyingcircus.encAddresses));
      }];
    })

    (mkIf cfgStatsRG.enable {
      environment.etc = {
        "local/statshost/metric-relabel.yaml.example".text = ''
          - source_labels: [ "__name__" ]
            regex: "re.*expr"
            action: drop
          - source_labels: [ "__name__" ]
            regex: "old_(.*)"
            replacement: "new_''${1}"
        '';
        "local/statshost/relays.json.example".text = ''
          [
            {
              "job_name": "otherproject",
              "proxy_url": "http://statshost-relay-otherproject.fcio.net:9090"
            }
          ]
        '';
        "local/statshost/README.txt".text =
          import ./README.nix config.networking.hostName;
      };

      # Update relayed nodes.
      systemd.services.fc-prometheus-update-relayed-nodes =
        (mkIf (relayRGNodes != []) {
          description = "Update prometheus proxy relayed nodes.";
          restartIfChanged = false;
          after = [ "network.target" ];
          wantedBy = [ "prometheus.service" ];
          serviceConfig = {
            User = "root";
            Type = "oneshot";
          };
          path = [ pkgs.curl pkgs.coreutils ];
          script = concatStringsSep "\n" (map
            (relayNode: ''
                curl -s -o /var/cache/.statshost-relay-${relayNode.job_name}.json.download \
                ${relayNode.proxy_url}/scrapeconfig.json && \
                mv /var/cache/.statshost-relay-${relayNode.job_name}.json.download /var/cache/statshost-relay-${relayNode.job_name}.json
              '')
            relayRGNodes);
        });

      systemd.timers.fc-prometheus-update-relayed-nodes =
        (mkIf (relayRGNodes != []) {
          description = "Timer for updating relayed targets";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnUnitActiveSec = "11m";
            RandomizedDelaySec = "3m";
          };
        });
      }
    )

    # An actual statshost. Enable Prometheus.
    (mkIf (cfgStatsGlobal.enable || cfgStatsRG.enable) {

      systemd.services.prometheus.serviceConfig = {
        # Prometheus can take a few minutes to shut down. If it is forcefully
        # killed, a crash recovery process is started, which takes even longer.
        TimeoutStopSec = "10m";
        # Prometheus uses a lot of connections, 1024 is not enough.
        LimitNOFILE = 65536;
      };

      services.prometheus =
        let
          remote_read = [
            { url = "http://localhost:8086/api/v1/prom/read?db=downsampled"; }
          ];
          remote_write = [
            {
              url = "http://localhost:8086/api/v1/prom/write?db=prometheus";
              queue_config = { capacity = 500000; max_backoff = "5s"; };
            }
          ];
        in
        {
          enable = true;
          extraFlags = promFlags;
          listenAddress = prometheusListenAddress;
          scrapeConfigs = [
            {
              job_name = "prometheus";
              scrape_interval = "5s";
              static_configs = [{
                targets = [ prometheusListenAddress ];
                labels = {
                  host = config.networking.hostName;
                };
              }];
            }
            rec {
              job_name = config.flyingcircus.enc.parameters.resource_group;
              scrape_interval = "15s";
              # We use a file sd here. Static config would restart prometheus
              # for each change. This way prometheus picks up the change
              # automatically and without restart.
              file_sd_configs = [{
                files = [ "${localDir}/scrape-*.json" ];
                refresh_interval = "10m";
              }];
              metric_relabel_configs =
                prometheusMetricRelabel ++
                (relabelConfiguration
                  "${localDir}/metric-relabel.${job_name}.yaml");
            }
            {
              job_name = "federate";
              scrape_interval = "15s";
              metrics_path = "/federate";
              honor_labels = true;
              params = {
                "match[]" = [ "{job=~\"static|prometheus\"}" ];
              };
              file_sd_configs = [{
                files = [ "${localDir}/federate-*.json" ];
                refresh_interval = "10m";
              }];
              metric_relabel_configs = prometheusMetricRelabel;
            }

          ] ++ relayRGConfig ++ relayLocationConfig;
          inherit remote_read remote_write;
        };

      environment.systemPackages = [ pkgs.influxdb ];

      services.influxdb = {
        enable = true;
        dataDir = "/srv/influxdb";
        extraConfig = {
          data = {
            index-version = "tsi1";
          };
          http = {
            enabled = true;
            auth-enabled = false;
            log-enabled = false;
          };
        };
      };

      systemd.services.influxdb = {
        serviceConfig = {
          LimitNOFILE = 65535;
          TimeoutStartSec = "1h";
          Restart = "always";
        };
        postStart =
          let influx = "${config.services.influxdb.package}/bin/influx";
          in ''
            echo 'SHOW CONTINUOUS QUERIES' | \
              ${influx} -format csv | \
              grep -q PROM_5M || \
              cat <<__EOF__ | ${influx}
              CREATE DATABASE prometheus;

              CREATE RETENTION POLICY "default"
                ON prometheus
                DURATION 1h REPLICATION 1 DEFAULT;

              CREATE DATABASE downsampled;
              CREATE RETENTION POLICY "5m"
                ON downsampled
                DURATION ${cfgStats.influxdbRetention}
                REPLICATION 1 DEFAULT;

              CREATE CONTINUOUS QUERY PROM_5M
                ON prometheus BEGIN
                  SELECT last(value) as value INTO downsampled."5m".:MEASUREMENT
                  FROM /.*/
                  GROUP BY TIME(5m),*
              END;
            __EOF__
          '';
      };

      flyingcircus.services.telegraf.inputs = {
        influxdb = [{
          urls = [ "http://localhost:8086/debug/vars" ];
          timeout = "10s";
        }];
      };

      flyingcircus.localConfigDirs.statshost = {
        dir = localDir;
      };

      flyingcircus.services.sensu-client.checks = {
        prometheus = {
          notification = "Prometheus http port alive";
          command = ''
            check_http -H ${config.networking.hostName} -p 9090 -u /metrics
          '';
        };
      };

    })

    # Grafana
    (mkIf (cfgStatsGlobal.enable || cfgStatsRG.enable) {

      networking.firewall = {
        allowedTCPPorts = [ 80 443 2004 ];
        allowedUDPPorts = [ 2003 ];
      };

      security.acme.certs = mkIf cfgStats.useSSL {
        ${cfgStats.hostName}.email = mkDefault "admin@flyingcircus.io";
      };

      services.grafana = {
        enable = true;
        port = 3001;
        addr = "127.0.0.1";
        rootUrl = "http://${cfgStats.hostName}/grafana";
        extraOptions = {
          AUTH_LDAP_ENABLED = "true";
          AUTH_LDAP_CONFIG_FILE = toString grafanaLdapConfig;
          # Grafana 7 changed the cookie path, so login fails if old session cookies are present.
          # Changing the cookie name helps.
          AUTH_LOGIN_COOKIE_NAME = "grafana7_session";
          LOG_LEVEL = "info";
          PATHS_PROVISIONING = grafanaProvisioningPath;
        };
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        virtualHosts.${cfgStats.hostName} = {
          enableACME = cfgStats.useSSL;
          forceSSL = cfgStats.useSSL;
          locations = {
            "/".extraConfig = ''
              rewrite ^/$ /grafana/ redirect;
              auth_basic "FCIO user";
              auth_basic_user_file "/etc/local/htpasswd_fcio_users";
              proxy_pass http://${prometheusListenAddress};
            '';
            "/grafana/".proxyPass = "http://127.0.0.1:3001/";
            "/grafana/public/".alias = "${pkgs.grafana}/share/grafana/public/";
          };
        };
      };

      systemd.services.grafana.preStart = let
        fcioDashboards = pkgs.writeTextFile {
          name = "fcio.yaml";
          text = ''
            apiVersion: 1
            providers:
            - name: 'default'
              orgId: 1
              folder: 'FCIO'
              type: file
              disableDeletion: false
              updateIntervalSeconds: 360
              options:
                path: ${grafanaJsonDashboardPath}
          '';
        };
        prometheusDatasource = pkgs.writeTextFile {
          name = "prometheus.yaml";
          text = ''
            apiVersion: 1
            datasources:
            - name: Prometheus
              type: prometheus
              access: proxy
              orgId: 1
              url: http://${config.networking.hostName}:9090
              editable: false
              isDefault: true
          '';
        };
      in ''
        rm -rf ${grafanaProvisioningPath}
        mkdir -p ${grafanaProvisioningPath}/dashboards ${grafanaProvisioningPath}/datasources
        ln -fs ${fcioDashboards} ${grafanaProvisioningPath}/dashboards/fcio.yaml
        ln -fs ${prometheusDatasource} ${grafanaProvisioningPath}/datasources/prometheus.yaml

      '';

      # Provide FC dashboards, and update them automatically.
      systemd.services.fc-grafana-load-dashboards = {
        description = "Update grafana dashboards.";
        restartIfChanged = false;
        after = [ "network.target" "grafana.service" ];
        wantedBy = [ "grafana.service" ];
        serviceConfig = {
          User = "grafana";
          Type = "oneshot";
        };
        path = with pkgs; [ git coreutils ];
        environment = {
          SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
        };
        script = ''
          if [[ -d ${grafanaJsonDashboardPath} && -d ${grafanaJsonDashboardPath}/.git ]];
          then
            cd ${grafanaJsonDashboardPath}
            git pull --ff-only
          else
            rm -rf ${grafanaJsonDashboardPath}
            git clone ${cfgStats.dashboardsRepository} ${grafanaJsonDashboardPath}
          fi
        '';
      };

      systemd.timers.fc-grafana-load-dashboards = {
        description = "Timer for updating the grafana dashboards";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnUnitActiveSec = "1h";
          RandomizedDelaySec = "3m";
        };
      };

    })

    # outgoing collectd proxy for this location
    (mkIf (cfgProxyLocation.enable && statshostService != null) {
      flyingcircus.services.collectdproxy.location = {
        enable = true;
        statshost = cfgStats.hostName;
        listenAddr = "::";
      };
      networking.firewall.extraCommands =
        "ip6tables -A nixos-fw -i ethsrv -p udp --dport 2003 -j nixos-fw-accept";
    })
  ];
}

# vim: set sw=2 et:
