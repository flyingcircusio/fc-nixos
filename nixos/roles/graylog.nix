# NOTES:
# * Mongo cluster setup requires manual intervention.
# * Logstash lumberjack plugin doesn't exist for graylog 3.x.
#   Use integrated beats support.

{ config, options, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.graylog;
  fclib = config.fclib;
  glAPIHAPort = 8002;
  gelfTCPHAPort = 12201;
  beatsTCPHAPort = 12301;
  listenFQDN = "${config.networking.hostName}.${config.networking.domain}";
  slash = addr: if fclib.isIp4 addr then "/32" else "/128";
  syslogInputPort = config.flyingcircus.services.graylog.syslogInputPort;
  gelfTCPGraylogPort = config.flyingcircus.services.graylog.gelfTCPGraylogPort;
  beatsTCPGraylogPort = config.flyingcircus.services.graylog.beatsTCPGraylogPort;
  glAPIPort = config.flyingcircus.services.graylog.apiPort;
  replSetName = if cfg.cluster then "graylog" else "";

  jsonConfig = (fromJSON
    (fclib.configFromFile /etc/local/graylog/graylog.json "{}"));

  # First cluster node becomes master
  clusterNodes =
    if cfg.cluster then
      lib.unique
        (filter
          (s: lib.any (serviceType: s.service == serviceType) cfg.serviceTypes)
          config.flyingcircus.encServices)
    # single-node "cluster"
    else [ { address = "${config.networking.hostName}.fcio.net"; ips = (fclib.listenAddresses "ethsrv"); } ];

  masterHostname =
    (head
      (lib.splitString
        "."
        (head clusterNodes).address));
in
{

  options = with lib; {

    flyingcircus.roles.graylog = {

      enable = mkEnableOption ''
          Graylog (3.x) role.

          Note: there can be multiple graylogs per RG, unlike loghost.
        '';

      serviceTypes = mkOption {
        type = types.listOf types.str;
        default = [ "graylog-server" ];
        description = ''
          Service types that should be considered when forming the cluster.
          Supported: graylog-server, loghost-server and loghost-location-graylog
        '';
      };

      cluster = mkOption {
        type = types.bool;
        default = true;
        description = "Build a GL cluster. Usually disabled by loghost role.";
      };

      publicFrontend = {

        enable = mkEnableOption "Configure Nginx for GL UI on FE at 80/443?";

        ssl = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable SSL via Let's Encrypt.
          '';
        };

        hostName = mkOption {
          type = types.nullOr types.str;
          default = "graylog.${config.flyingcircus.enc.parameters.resource_group}.fcio.net";
          description = "HTTP host name for the GL frontend.";
          example = "graylog.example.com";
        };
      };
    };
  };

  config = lib.mkMerge [

    (lib.mkIf (cfg.enable && cfg.publicFrontend.enable) {
      services.nginx.virtualHosts."${cfg.publicFrontend.hostName}" = {
        enableACME = cfg.publicFrontend.ssl;
        forceSSL = cfg.publicFrontend.ssl;
        locations = {
          "/" = {
            proxyPass = "http://${listenFQDN}:${toString glAPIHAPort}";
            extraConfig = ''
              proxy_set_header Remote-User "";
              proxy_set_header X-Graylog-Server-URL https://${cfg.publicFrontend.hostName}/;
            '';
          };
          "/admin" = {
            proxyPass = "http://${listenFQDN}:${toString glAPIHAPort}";
            extraConfig = ''
              auth_basic "FCIO user";
              auth_basic_user_file "/etc/local/nginx/htpasswd_fcio_users";
            '';
          };
        };
      };
    })

    (lib.mkIf (jsonConfig ? heapPercentage) {
      flyingcircus.services.graylog.heapPercentage = jsonConfig.heapPercentage;
    })

    (lib.mkIf (jsonConfig ? publicFrontend) {
      flyingcircus.roles.graylog.publicFrontend.enable = jsonConfig.publicFrontend;
    })

    (lib.mkIf (jsonConfig ? publicFrontendHostname) {
      flyingcircus.roles.graylog.publicFrontend.hostName = jsonConfig.publicFrontendHostname;
    })

    (lib.mkIf cfg.enable {

      networking.firewall.allowedTCPPorts = [ 9002 ];

      networking.firewall.extraCommands = ''
        ip46tables -A nixos-fw -i ethsrv -p udp --dport ${toString syslogInputPort} -j nixos-fw-accept
        ip46tables -A nixos-fw -i ethsrv -p tcp --dport ${toString beatsTCPHAPort} -j nixos-fw-accept
      '';

      flyingcircus.services.graylog = {

        enable = true;
        isMaster = masterHostname == config.networking.hostName;

        mongodbUri = let
          repl = if (length clusterNodes) > 1 then "?replicaSet=${replSetName}" else "";
          mongodbNodes = concatStringsSep ","
              (map (node: "${fclib.quoteIPv6Address (head (filter fclib.isIp6 node.ips))}:27017") clusterNodes);
          in
            "mongodb://${mongodbNodes}/graylog${repl}";

        config = jsonConfig.extraGraylogConfig or {};

      };

      flyingcircus.roles.mongodb40.enable = true;

      systemd.services.fc-loghost-mongodb-set-feature-compat-version = {
        partOf = [ "mongodb.service" ];
        wantedBy = [ "mongodb.service" ];
        after = [ "mongodb.service" ];

        serviceConfig = {
          ExecStart = let
            js = pkgs.writeText "mongodb_set_feature_compat_version_4_0.js" ''
              res = db.adminCommand({"getParameter": 1, "featureCompatibilityVersion": 1});
              compat_version = res["featureCompatibilityVersion"]["version"];

              if (db.version().startsWith("4.0") && compat_version == "3.6") {
                  print("MongoDB: current feature compat version is 3.6, updating to 4.0");
                  db.adminCommand( { setFeatureCompatibilityVersion: "4.0" } );
              }
            '';
          in "${pkgs.mongodb-4_0}/bin/mongo ${js}";

          Restart = "on-failure";
          Type = "oneshot";
          RemainAfterExit = "true";
        };
      };

      services.mongodb.replSetName = replSetName;
      services.mongodb.extraConfig = ''
        storage.wiredTiger.engineConfig.cacheSizeGB: 1
      '';

      flyingcircus.services.nginx.enable = true;

      flyingcircus.localConfigDirs.graylog = {
        dir = "/etc/local/graylog";
        user = "graylog";
      };

      environment.etc."local/graylog/README.txt".text = ''
        Graylog (${config.services.graylog.package.version}) is running on this machine.

        If you need to set non-default configuration options, you can put a
        file called `graylog.json` into this directory.
        Have a look at graylog.json.example in this directory.

        Available options:

        * publicFrontend: set to true to serve the Graylog dashboard on
          the public interface via HTTPS.
        * publicFrontendHostname: set hostname for Graylog dashboard,
          default is ${options.flyingcircus.roles.graylog.publicFrontend.hostName.default}.
        * heapPercentage (int): Fraction of system memory that is used for
          Graylog, in percent.
        * extraGraylogConfig (object): Addional config params supported by
          Graylog's server config file.
          See https://docs.graylog.org/en/3.0/pages/configuration/server.conf.html.

        '';

      environment.etc."local/graylog/graylog.json.example".text = ''
        {
          "publicFrontend": true,
          "heapPercentage": 70,
          "extraGraylogConfig": {
            "processbuffer_processors": 4,
            "trusted_proxies": "127.0.0.1/32, 0:0:0:0:0:0:0:1/128"
          }
        }
      '';

      services.nginx.virtualHosts."${cfg.publicFrontend.hostName}:9002" =
      let
        mkListen = addr: { inherit addr; port = 9002; };
      in {
        listen = map mkListen (fclib.listenAddressesQuotedV6 "ethsrv");
        locations = {
          "/" = {
            proxyPass = "http://${listenFQDN}:${toString glAPIHAPort}";
            extraConfig = ''
              # Direct access w/o prior authentication. This is useful for API access.
              # Strip Remote-User as there is nothing in between the user and us.
              proxy_set_header Remote-User "";
              proxy_set_header X-Graylog-Server-URL http://${listenFQDN}:9002/;
            '';
          };
        };
      };
      # HAProxy load balancer.
      # Since haproxy is rather lightweight we just fire up one on each graylog
      # node, talking to all known graylog nodes.
      flyingcircus.services.haproxy.enable = true;

      services.haproxy.config = lib.mkOverride 90 (let
        # graylog is only listening for IPv6
        backendConfig = config: lib.concatStringsSep "\n"
          (map
            (node: "    " + (config node.address (head (filter fclib.isIp6 node.ips))))
            clusterNodes);

        listenConfig = port: lib.concatStringsSep "\n"
          (map
            (addr: "    bind ${addr}:${toString port}")
            (fclib.listenAddresses "ethsrv"));
      in ''
        global
            daemon
            chroot /var/empty
            maxconn 4096
            log localhost local2

        defaults
            mode http
            log global
            option dontlognull
            option http-keep-alive
            option redispatch

            timeout connect 5s
            timeout client 30s    # should be equal to server timeout
            timeout server 30s    # should be equal to client timeout
            timeout queue 30s

        frontend gelf-tcp-in
        ${listenConfig gelfTCPHAPort}
            mode tcp
            option tcplog
            timeout client 10s # should be equal to server timeout

            default_backend gelf_tcp

        frontend beats-tcp-in
        ${listenConfig beatsTCPHAPort}
            mode tcp
            option tcplog
            # Journalbeat uses long-running connections and may send nothing
            # for a while. Use ttl 120s for Journalbeat to make sure it
            # reconnects before it's thrown out by HAproxy.
            timeout client 121s

            default_backend beats_tcp

        frontend graylog_http
        ${listenConfig glAPIHAPort}
            use_backend stats if { path_beg /admin/stats }
            option httplog
            timeout client 121s    # should be equal to server timeout
            default_backend graylog

        backend gelf_tcp
            mode tcp
            balance leastconn
            option httpchk HEAD /api/system/lbstatus
            timeout server 10s
            timeout tunnel 61s
        ${backendConfig (name: ip:
            "server ${name}  ${ip}:${toString gelfTCPGraylogPort} check port ${toString glAPIPort} inter 10s rise 2 fall 1")}

        backend beats_tcp
            mode tcp
            balance leastconn
            option httpchk HEAD /api/system/lbstatus
            timeout server 121s
        ${backendConfig (name: ip:
            "server ${name}  ${ip}:${toString beatsTCPGraylogPort} check port ${toString glAPIPort} inter 10s rise 2 fall 1")}

        backend graylog
            balance roundrobin
            option httpchk GET /
            timeout server 121s    # should be equal to client timeout
        ${backendConfig (name: ip:
            "server ${name}  ${ip}:${toString glAPIPort} check fall 1 rise 2 inter 10s maxconn 20")}

        backend stats
            stats uri /
            stats refresh 5s
      '');
    })

    {
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        {
          source_labels = [ "__name__" ];
          regex = "(org_graylog2)_(.*)$";
          replacement = "graylog_\${2}";
          target_label = "__name__";
        }
      ];
    }

  ];
}
