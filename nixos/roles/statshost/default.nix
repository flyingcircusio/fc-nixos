# Statshost: an Prometheus/Grafana server.
# TODO: don't build if more than one location relay is active in the same location.
# Having more than one breaks prometheus.
{
  config,
  options,
  lib,
  pkgs,
  ...
}:

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

  cfgLokiRG = config.flyingcircus.roles.loki;

  promFlags = [
    "--storage.tsdb.retention.time ${toString cfgStats.prometheusRetention}d"
  ];
  prometheusListenAddress = cfgStats.prometheusListenAddress;

  customRelabelPath = "${localDir}/metric-relabel.yaml";
  customRelabelConfig = relabelConfiguration customRelabelPath;
  customRelabelJSON =
    filename:
    pkgs.runCommand "${baseNameOf filename}.json" {
      buildInputs = [ pkgs.remarshal ];
      preferLocalBuild = true;
    } "remarshal -if yaml -of json < ${filename} > $out";

  relabelConfiguration =
    filename: if pathExists filename then fromJSON (readFile (customRelabelJSON filename)) else [ ];

  prometheusMetricRelabel = cfgStats.prometheusMetricRelabel ++ customRelabelConfig;

  relayRGNodes = fclib.jsonFromFile "${localDir}/relays.json" "[]";

  relayLocationNodes = map (
    proxy:
    {
      job_name = proxy.location;
      proxy_url = "https://${proxy.address}:9443";
    }
    // cfgStats.prometheusLocationProxyExtraSettings
  ) relayLocationProxies;

  relayLocationProxies =
    # We need the FE address, which is not published by directory. I'd think
    # "interface" should become an attribute in the services table.
    let
      makeFE =
        s:
        let
          proxyHostname = removeSuffix ".fcio.net" (removeSuffix ".gocept.net" s.address);
        in
        "${proxyHostname}.fe.${s.location}.fcio.net";
    in
    map (service: service // { address = makeFE service; }) (
      filter (s: s.service == "statshostproxy-location") config.flyingcircus.encServices
    );

  buildRelayConfig =
    relayNodes: nodeConfig:
    map (
      relayNode:
      {
        scrape_interval = cfgStats.prometheusScrapeInterval;
        file_sd_configs = [
          {
            files = [ (nodeConfig relayNode) ];
            refresh_interval = "10m";
          }
        ];
        metric_relabel_configs =
          prometheusMetricRelabel
          ++ (relabelConfiguration "${localDir}/metric-relabel.${relayNode.job_name}.yaml");
      }
      // relayNode
    ) relayNodes;

  relayRGConfig = buildRelayConfig relayRGNodes (
    relayNode: "/var/cache/statshost-relay-${relayNode.job_name}.json"
  );

  relayLocationConfig = buildRelayConfig relayLocationNodes (
    relayNode: "/etc/current-config/statshost-relay-${relayNode.job_name}.json"
  );

  statshostService = findFirst (
    s: s.service == "statshost-collector"
  ) null config.flyingcircus.encServices;

  grafanaJsonDashboardPath = "${config.services.grafana.dataDir}/dashboards";
  grafanaProvisioningPath = "${config.services.grafana.dataDir}/provisioning";

in
{

  imports = [
    ./global-metrics.nix
    ./location-proxy.nix
    ./relabel.nix
    ./rg-relay.nix

    (mkRenamedOptionModule
      [ "flyingcircus" "roles" "statshost" "ldapMemberOf" ]
      [ "flyingcircus" "roles" "statshost" "ldap" "memberOf" ]
    )
  ];

  options = {

    # Options that are used by RG and the global statshost.
    flyingcircus.roles.statshost = {

      supportsContainers = fclib.mkDisableDevhostSupport;

      hostName = mkOption {
        default = "grafana.${config.flyingcircus.enc.parameters.resource_group}.fcio.net";
        defaultText = "grafana.<resource group>.fcio.net";
        type = types.str;
        description = ''
          Host name for the Grafana frontend.
          A Letsencrypt certificate is generated for it.
          Defaults to the FE FQDN.
        '';
        example = "stats.example.com";
      };

      ldap = {
        enable = mkEnableOption "Enable LDAP for Grafana";

        memberOf = mkOption {
          default = config.flyingcircus.enc.parameters.resource_group;
          defaultText = "The VM's resource group";
          type = types.str;
          description = ''
            LDAP group to use for the "memberOf" attribute.
            Defaults to the resource group.
            Checks if the user is a member of this group to grant access.
          '';
          example = "cn=stats,ou=Group,dc=gocept,dc=com";
        };

        server = mkOption {
          type = types.str;
          default = "ldap.fcio.net";
        };

      };

      oidc = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable OIDC for Grafana";
        };

        realm = mkOption {
          type = types.str;
          default = "fcio";
        };

        server = mkOption {
          type = types.str;
          default = "https://auth.flyingcircus.io";
        };
      };

      useSSL = mkOption {
        type = types.bool;
        description = "Whether to require HTTPS for Grafana dashboard access.";
        default = true;
      };

      prometheusMetricRelabel = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = "Prometheus metric relabel configuration.";
      };

      prometheusLocationProxyExtraSettings = mkOption {
        type = types.attrs;
        default = { };
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
        defaultText = "\${head fclib.network.srv.dualstack.addressQuoted}:9090";
        description = "Prometheus listen address";
      };

      prometheusScrapeInterval = mkOption {
        type = types.str;
        default = "15s";
        description = "How often metrics are scraped.";
        example = "1m";
      };

      prometheusRetention = mkOption {
        type = types.int;
        default = 100;
        description = "How long to keep data in *days*.";
      };
    };

    # FC infrastructure global stats host
    flyingcircus.roles.statshost-global = {

      enable = mkEnableOption "Grafana/Prometheus stats host (global)";
      supportsContainers = fclib.mkDisableDevhostSupport;

      allowedMetricPrefixes = mkOption {
        type = types.listOf types.str;
        default = [ ];
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
      supportsContainers = fclib.mkDisableDevhostSupport;
    };

    # The following two roles are "customer" roles, customers can use them to
    # have their own statshost.
    flyingcircus.roles.statshost-master = {
      enable = mkEnableOption "Grafana/Prometheus stats host for one RG";
      supportsContainers = fclib.mkDisableDevhostSupport;
    };

    flyingcircus.roles.statshost-relay = {
      enable = mkEnableOption "RG-specific Grafana/Prometheus stats relay";
      supportsContainers = fclib.mkDisableDevhostSupport;
    };

  };

  config = mkMerge [
    # Global stats host.
    (mkIf cfgStatsGlobal.enable {
      boot.kernel.sysctl."net.core.rmem_max" = mkOverride 90 25165824;

      # Global prometheus configuration
      environment.etc = listToAttrs (
        map (
          p:
          nameValuePair "current-config/statshost-relay-${p.location}.json" {
            text = toJSON [
              {
                targets = (
                  map (s: "${s.node}:9126") (
                    filter (
                      s: s.service == "statshost-collector" && s.location == p.location
                    ) config.flyingcircus.encServiceClients
                  )
                );
              }
            ];
          }
        ) relayLocationProxies
      );

      flyingcircus.roles.statshost.ldap.memberOf = "crew";
    })

    (mkIf (cfgStatsRG.enable || cfgProxyRG.enable) {
      environment.etc."local/statshost/scrape-rg.json".text = toJSON [
        {
          targets = sort lessThan (
            unique (map (host: "${host.name}.fcio.net:9126") config.flyingcircus.encAddresses)
          );
        }
      ];
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
        "local/statshost/README.txt".text = import ./README.nix config.networking.hostName;
      };

      # Update relayed nodes.
      systemd.services.fc-prometheus-update-relayed-nodes = (
        mkIf (relayRGNodes != [ ]) {
          description = "Update prometheus proxy relayed nodes.";
          restartIfChanged = false;
          after = [ "network.target" ];
          wantedBy = [ "prometheus.service" ];
          serviceConfig = {
            User = "root";
            Type = "oneshot";
          };
          path = [
            pkgs.curl
            pkgs.coreutils
          ];
          script = concatStringsSep "\n" (
            map (relayNode: ''
              curl -s -o /var/cache/.statshost-relay-${relayNode.job_name}.json.download \
              ${relayNode.proxy_url}/scrapeconfig.json && \
              mv /var/cache/.statshost-relay-${relayNode.job_name}.json.download /var/cache/statshost-relay-${relayNode.job_name}.json
            '') relayRGNodes
          );
        }
      );

      systemd.timers.fc-prometheus-update-relayed-nodes = (
        mkIf (relayRGNodes != [ ]) {
          description = "Timer for updating relayed targets";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnUnitActiveSec = "11m";
            RandomizedDelaySec = "3m";
          };
        }
      );
    })

    # An actual statshost. Enable Prometheus.
    (mkIf (cfgStatsGlobal.enable || cfgStatsRG.enable) {

      systemd.services.prometheus.serviceConfig = {
        # Prometheus can take a few minutes to shut down. If it is forcefully
        # killed, a crash recovery process is started, which takes even longer.
        TimeoutStopSec = "10m";
        # Prometheus uses a lot of connections, 1024 is not enough.
        LimitNOFILE = 65536;
      };

      services.prometheus = {
        enable = true;
        extraFlags = promFlags;
        listenAddress = prometheusListenAddress;
        scrapeConfigs = [
          {
            job_name = "prometheus";
            scrape_interval = "5s";
            static_configs = [
              {
                targets = [ prometheusListenAddress ];
                labels = {
                  host = config.networking.hostName;
                };
              }
            ];
          }
          rec {
            job_name = config.flyingcircus.enc.parameters.resource_group;
            scrape_interval = cfgStats.prometheusScrapeInterval;
            # We use a file sd here. Static config would restart prometheus
            # for each change. This way prometheus picks up the change
            # automatically and without restart.
            file_sd_configs = [
              {
                files = [ "${localDir}/scrape-*.json" ];
                refresh_interval = "10m";
              }
            ];
            metric_relabel_configs =
              prometheusMetricRelabel ++ (relabelConfiguration "${localDir}/metric-relabel.${job_name}.yaml");
          }
          {
            job_name = "federate";
            scrape_interval = cfgStats.prometheusScrapeInterval;
            metrics_path = "/federate";
            honor_labels = true;
            params = {
              "match[]" = [ "{job=~\"static|prometheus\"}" ];
            };
            file_sd_configs = [
              {
                files = [ "${localDir}/federate-*.json" ];
                refresh_interval = "10m";
              }
            ];
            metric_relabel_configs = prometheusMetricRelabel;
          }

        ]
        ++ relayRGConfig
        ++ relayLocationConfig;
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
        allowedTCPPorts = [
          80
          443
          2004
        ];
        allowedUDPPorts = [ 2003 ];
      };

      security.acme.certs = mkIf cfgStats.useSSL {
        "${cfgStats.hostName}".email = mkDefault "admin@flyingcircus.io";
      };

      services.grafana = {
        enable = true;
        settings = {
          auth = {
            login_cookie_name = "grafana9_session";
          };

          # We only support LDAP and OIDC, no local login.
          "auth.basic" = {
            enabled = false;
          };

          paths = {
            provisioning = grafanaProvisioningPath;
          };

          server = {
            http_port = 3001;
            http_addr = "127.0.0.1";
            root_url = "https://${cfgStats.hostName}/grafana/";
          };
          security = {
            disable_initial_admin_creation = true;
            # This is the key previously set as default in Nixpkgs.
            # TODO: PL-135228
            secret_key = "SW2YcwTIb9zpOOhoPsMm";
          };
        };
      };

      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        appendHttpConfig = ''
          map $http_referer $redirect_referer {
              "~^https://${cfgStats.hostName}/grafana/" 1;
              default 0;
          }
        '';
        virtualHosts.${cfgStats.hostName} = {
          enableACME = cfgStats.useSSL;
          forceSSL = cfgStats.useSSL;
          locations = {
            "/".extraConfig = ''
              if ($redirect_referer) {
                  rewrite ^(.*)$ /grafana$1 redirect;
              }

              rewrite ^/$ /grafana/ redirect;
              auth_basic "FCIO user";
              auth_basic_user_file "/etc/local/htpasswd_fcio_users";
              proxy_pass http://${prometheusListenAddress};
            '';
            "/grafana/" = {
              proxyPass = "http://127.0.0.1:3001/";
              proxyWebsockets = true;
            };
          };
        };
      };

      systemd.services.grafana.preStart =
        let
          fcioDashboards = pkgs.writeTextFile {
            name = "fcio.yaml";
            text = ''
              apiVersion: 1
              providers:
              - name: 'default'
                orgId: 1
                type: file
                disableDeletion: false
                updateIntervalSeconds: 360
                options:
                  path: ${grafanaJsonDashboardPath}
                  foldersFromFilesStructure: true
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

          # support loki/tempo running on the same host as grafana in
          # single-RG mode.
          lokiDatasource = pkgs.writeTextFile {
            name = "loki.yaml";
            text = ''
              apiVersion: 1
              deleteDatasources:
              - name: Loki
                orgId: 1
              datasources:
              - name: FCIO Loki
                type: loki
                uid: fcioloki
                access: proxy
                orgId: 1
                url: http://localhost:3100
                editable: false
                isDefault: false
            '';
          };
          tempoDatasource = pkgs.writeTextFile {
            name = "tempo.yaml";
            text = ''
              apiVersion: 1
              deleteDatasources:
              - name: tempo
                orgId: 1
              datasources:
              - name: FCIO Tempo
                type: tempo
                uid: fciotempo
                access: proxy
                orgId: 1
                url: http://localhost:3200
                editable: false
                isDefault: false
                basicAuth: false
                jsonData:
                   tracesToLogsV2:
                     # Field with an internal link pointing to a logs data source in Grafana.
                     # datasourceUid value must match the uid value of the logs data source.
                     datasourceUid: 'fcioloki'
                     spanStartTimeShift: '-1h'
                     spanEndTimeShift: '1h'
                     tags: []
                     filterByTraceID: false
                     filterBySpanID: false
                     customQuery: false
                   tracesToMetrics:
                     datasourceUid: 'fcioprometheus'
                     spanStartTimeShift: '-1h'
                     spanEndTimeShift: '1h'
                     tags: []
                     queries: []
                   nodeGraph:
                     enabled: true
                   search:
                     hide: false
                   traceQuery:
                     timeShiftEnabled: true
                     spanStartTimeShift: '-1h'
                     spanEndTimeShift: '1h'
                   streamingEnabled:
                     search: true
                     metrics: true
            '';
          };
        in
        ''
          rm -rf ${grafanaProvisioningPath}
          mkdir -p ${grafanaProvisioningPath}/dashboards ${grafanaProvisioningPath}/datasources
          ln -fs ${fcioDashboards} ${grafanaProvisioningPath}/dashboards/fcio.yaml
          ln -fs ${prometheusDatasource} ${grafanaProvisioningPath}/datasources/prometheus.yaml
        ''
        + optionalString (cfgStatsRG.enable && cfgLokiRG.enable) ''
          ln -fs ${lokiDatasource} ${grafanaProvisioningPath}/datasources/loki.yaml
        ''
        + optionalString (cfgStatsRG.enable && cfgLokiRG.enable) ''
          ln -fs ${tempoDatasource} ${grafanaProvisioningPath}/datasources/tempo.yaml
        '';

      # Provide FC dashboards, and update them automatically.
      systemd.services.fc-grafana-load-dashboards = {
        description = "Update grafana dashboards.";
        restartIfChanged = false;
        after = [
          "network.target"
          "grafana.service"
        ];
        wantedBy = [ "grafana.service" ];
        serviceConfig = {
          User = "grafana";
          Type = "oneshot";
        };
        path = with pkgs; [
          git
          coreutils
        ];
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

    # SSO for statshost-master. LDAP and OIDC (default) are supported.
    # Not affected: statshost-global (uses local SSO config).

    (lib.mkIf (cfgStatsRG.enable && cfgStats.ldap.enable) {
      services.grafana.settings."auth.ldap" = {
        enabled = true;
        config_file = toString (
          pkgs.writeText "ldap.toml" ''
            verbose_logging = true

            [[servers]]
            host = "${cfgStats.ldap.server}"
            port = 636
            start_tls = false
            use_ssl = true
            bind_dn = "uid=%s,ou=People,dc=gocept,dc=com"
            search_base_dns = ["ou=People,dc=gocept,dc=com"]
            search_filter = "(&(&(objectClass=inetOrgPerson)(uid=%s))(memberOf=cn=${cfgStats.ldap.memberOf},ou=GroupOfNames,dc=gocept,dc=com))"
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
          ''
        );
      };
    })

    (lib.mkIf (cfgStatsRG.enable && cfgStats.oidc.enable) {
      services.grafana.settings = {
        auth = {
          disable_login_form = true;
          oauth_allow_insecure_email_lookup = true;
        };

        # We expect that we are talking to our default Keycloak and that a OIDC
        # client has been set up automatically by the directory when activating
        # statshost-master role.
        "auth.generic_oauth" =
          let
            realmUrl = "${cfgStats.oidc.server}/realms/${cfgStats.oidc.realm}";
          in
          {
            enabled = true;
            auto_login = true;
            name = "FCIO oidc";
            allow_sign_up = true;
            client_id = "${config.networking.hostName}_statshost-master";
            client_secret = fclib.derivePasswordForHost "oidc_statshost-master";
            scopes = "openid email profile";
            email_attribute_path = "email";
            login_attribute_path = "preferred_username";
            name_attribute_path = "full_name";
            # Everybody becomes admin, ignoring user roles from OIDC.
            role_attribute_path = "\"'Admin'\"";
            auth_url = "${realmUrl}/protocol/openid-connect/auth";
            token_url = "${realmUrl}/protocol/openid-connect/token";
          };
      };
    })
  ];
}

# vim: set sw=2 et:
