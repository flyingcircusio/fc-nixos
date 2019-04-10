# Relay stats of a location via NGINX
{ config, lib, pkgs, ... }:
with lib;
let
  fclib = import ../../lib;
  statshostServiceIPs = fclib.listServiceIPs config "statshost-collector";
  port = 9090;
in
{
  config = mkIf (
      config.flyingcircus.roles.statshostproxy.enable &&
      statshostServiceIPs != []) {

    networking.firewall.extraCommands =
     "# statshost-collector\n" + concatStringsSep ""
        (map
          (ip: ''
            ${fclib.iptables ip} -A nixos-fw -i ethfe -s ${ip} -p tcp \
              --dport ${toString port} -j nixos-fw-accept
          '')
          statshostServiceIPs);

    # XXX use upstream nginx service instead
    # flyingcircus.roles.nginx.enable = true;
    # flyingcircus.roles.nginx.httpConfig = ''
    #   server {
    #     # XXX HTTPS!
    #     ${fclib.nginxListenOn config "ethfe" port}

    #     access_log /var/log/nginx/statshost_access.log;
    #     error_log /var/log/nginx/statshost_error.log;

    #     location / {
    #         resolver ${concatStringsSep " " config.networking.nameservers};
    #         proxy_pass http://$http_host$request_uri$is_args$args;
    #     }
    #   }
    # '';

  };
}
