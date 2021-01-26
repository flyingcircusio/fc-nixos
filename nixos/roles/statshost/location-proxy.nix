# Relay stats of a location via NGINX.

{ config, lib, pkgs, ... }:
with lib;
let
  fclib = config.fclib;
  statshostServiceIPs = fclib.listServiceIPs "statshost-collector";
  domain = config.networking.domain;
  location = lib.attrByPath [ "parameters" "location" ] "standalone" config.flyingcircus.enc;
  feFQDN = "${config.networking.hostName}.fe.${location}.${domain}";
  httpPort = 9090;
  httpsPort = 9443;
in
{
  config = mkIf (
      config.flyingcircus.roles.statshost-location-proxy.enable &&
      statshostServiceIPs != []) {

    networking.firewall.extraCommands = let
      rule = ip: port: ''
        ${fclib.iptables ip} -A nixos-fw -i ethfe -s ${ip} -p tcp \
          --dport ${toString port} -j nixos-fw-accept
      '';
     in "# statshost-collector\n" + concatStringsSep ""
        (map (ip: (rule ip httpPort) + (rule ip httpsPort)) statshostServiceIPs);

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      virtualHosts."${feFQDN}" = {
        serverAliases = [ "${config.networking.hostName}.${config.networking.domain}" ];
        enableACME = true;
        addSSL = true;
        listen =
          flatten
            (map
              (a: [{ addr = a; port = httpsPort; ssl = true; }
                   { addr = a; port = httpPort; }])
              (fclib.listenAddressesQuotedV6 "ethfe"));
        locations = {
          "/" = {
            extraConfig = ''
              resolver ${concatStringsSep " " config.networking.nameservers};
              limit_except GET { deny all; }
            '';
            proxyPass = "http://$host:9126$request_uri$is_args$args";

          };
        };
        extraConfig = ''
          access_log /var/log/nginx/statshost-location-proxy_access.log;
          error_log /var/log/nginx/statshost-location-proxy_error.log;
        '';
      };
    };

  };
}
