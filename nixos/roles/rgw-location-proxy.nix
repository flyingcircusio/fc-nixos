{
  config,
  lib,
  ...
}:
let
  inherit (config) fclib;
  cfg = config.flyingcircus.roles.rgw-location-proxy;
  haproxyPort = toString 7475;
in
{
  options.flyingcircus.roles.rgw-location-proxy = {
    enable = lib.mkEnableOption "CEPH RGW location proxy";

    domain = lib.mkOption {
      type = lib.types.str;
      default = lib.concatStringsSep "." (
        [
          "objects"
          config.flyingcircus.location
        ]
        ++ lib.optionals (config.flyingcircus.enc.parameters.resource_group != "services") [
          config.flyingcircus.enc.parameters.resource_group
        ]
        ++ [ "fcio.net" ]
      );
      defaultText = "objects.<location>.<resource_group>.fcio.net";
      description = ''
        Domain where the object gateway is publicly exposed.
      '';
    };

    dns01CredFile = lib.mkOption {
      type = lib.types.pathWith {
        absolute = true;
        inStore = false;
      };
      default = "/etc/local/nixos/rgw-dns01.env";
      description = ''
        Path to the file containing credentials for the DNS01 challenge. Must have the format
        ```
        PDNS_API_KEY=<api-key>
        PDNS_API_URL=https://dns.flyingcircus.io/
        PDNS_PROPAGATION_TIMEOUT=3610
        ```
      '';
    };
  };

  config = (
    lib.mkIf cfg.enable {
      flyingcircus.services.nginx = {
        enable = true;
        virtualHosts.${cfg.domain} = lib.mkMerge [
          {
            forceSSL = true;
            enableACME = false;
            useACMEHost = cfg.domain;
            locations."/".proxyPass = "http://[::1]:${haproxyPort}";
            extraConfig = ''
              proxy_max_temp_file_size 0;
              client_max_body_size 10000m;
              proxy_request_buffering off;
            '';
          }
        ];
      };

      security.acme.certs.${cfg.domain} = {
        dnsProvider = fclib.mkPlatform "pdns";
        credentialsFile = cfg.dns01CredFile;
        webroot = lib.mkForce null;
        group = "nginx";
      };

      flyingcircus.services.haproxy = {
        enable = true;
        enableStructuredConfig = true;

        frontend = {
          http-in = {
            binds = [ "[::1]:${haproxyPort}" ];
            default_backend = "s3";
          };
        };

        backend = {
          s3 = {
            servers = map (
              service:
              let
                name = builtins.head (lib.splitString "." service.address);
                address = builtins.head (builtins.filter fclib.isIp4 service.ips);
              in
              "s3-${name} ${address}:7480 check inter 10s rise 2 fall 1 maxconn 1000"
            ) (fclib.findServices "ceph_rgw-server");
            extraConfig = ''
              option httpchk GET /rgw-monitoring/probe
            '';
          };
        };
      };
      # We have >=2 object storage gateways per location. To have a redundant setup,
      # only one of them should be in maintenance
      flyingcircus.agent.maintenanceConstraints.machinesInService = map (
        service: builtins.head (lib.splitString "." service.address)
      ) (fclib.findServices "rgw-location-proxy-rgw-location-proxy");
    }
  );
}
