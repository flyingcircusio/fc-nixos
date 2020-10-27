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
  listenFQDN = "${config.networking.hostName}.${config.networking.domain}";
  slash = addr: if fclib.isIp4 addr then "/32" else "/128";
  syslogInputPort = config.flyingcircus.services.graylog.syslogInputPort;
  gelfTCPGraylogPort = config.flyingcircus.services.graylog.gelfTCPGraylogPort;
  glAPIPort = config.flyingcircus.services.graylog.apiPort;
  replSetName = if cfg.cluster then "graylog" else "";

  jsonConfig = (fromJSON
    (fclib.configFromFile /etc/local/graylog/graylog.json "{}"));

  # First graylog or loghost node becomes master
  glNodes =
    fclib.listServiceAddresses "loghost-server" ++
    fclib.listServiceAddresses "graylog-server";

  logTargets = lib.unique (
    # Pick one of the regular graylog servers ...
    (if (length glNodes > 0) then
      [(head glNodes)] else []) ++

    # ... and add the central one (if it exists).
    (fclib.listServiceAddresses "loghost-location-server"));

  masterHostname =
    (head
      (lib.splitString
        "."
        (head glNodes)));
in
{

  options = with lib; {

    flyingcircus.roles.graylog = {

      enable = mkEnableOption ''
          Graylog (3.x) role.

          Note: there can be multiple graylogs per RG, unlike loghost.
        '';

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

      networking.firewall.extraCommands =
        "ip46tables -A nixos-fw -i ethsrv -p udp --dport ${toString syslogInputPort} -j nixos-fw-accept";

      flyingcircus.services.graylog = {

        enable = true;
        isMaster = masterHostname == config.networking.hostName;

        mongodbUri = let
          repl = if cfg.cluster then "?replicaSet=${replSetName}" else "";
          mongodbNodes = concatStringsSep ","
              (map (node: "${node}:27017") glNodes);
          in
            "mongodb://${mongodbNodes}/graylog${repl}";

        config = jsonConfig.extraGraylogConfig or {};

      };

      flyingcircus.roles.mongodb36.enable = true;
      services.mongodb.replSetName = replSetName;
      services.mongodb.extraConfig = ''
        storage.wiredTiger.engineConfig.cacheSizeGB: 1
      '';

      flyingcircus.roles.nginx.enable = true;

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

      services.haproxy.config = lib.mkForce (let
        nodes =
          filter
            (s: s.service == "loghost-server" || s.service == "graylog-server" || s.service == "loghost-location-server")
            config.flyingcircus.encServices;

        # graylog is only listening for IPv6
        backendConfig = config: lib.concatStringsSep "\n"
          (map
            (node: "    " + (config node.address (head (filter fclib.isIp6 node.ips))))
            nodes);

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

    (lib.mkIf (length logTargets > 0) {
      # Forward all syslog to graylog, if there is one.
      flyingcircus.syslog.extraRules = concatStringsSep "\n"
              (map (target: "*.* @${target}:${toString syslogInputPort};RSYSLOG_SyslogProtocol23Format") logTargets);
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
