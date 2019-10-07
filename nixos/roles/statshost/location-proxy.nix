# Relay stats of a location via NGINX.
# TODO: Write a test.
# TODO: HTTPS!
# TODO: Rename, the role name should say that it's acting as a location proxy.

{ config, lib, pkgs, ... }:
with lib;
let
  fclib = config.fclib;
  statshostServiceIPs = fclib.listServiceIPs "statshost-collector";
  port = 9090;
in
{
  config = mkIf (
      config.flyingcircus.roles.statshostproxy.enable &&
      statshostServiceIPs != []) {

    assertions = [ 
      { 
        assertion = false;
        message = ''
          Role statshostproxy is untested and may break things.
          Don't enable this multiple times in a location!
        '';
      }
    ];

    networking.firewall.extraCommands =
     "# statshost-collector\n" + concatStringsSep ""
        (map
          (ip: ''
            ${fclib.iptables ip} -A nixos-fw -i ethfe -s ${ip} -p tcp \
              --dport ${toString port} -j nixos-fw-accept
          '')
          statshostServiceIPs);

    services.nginx.enable = true;
    services.nginx.appendHttpConfig = ''
      server {
        ${fclib.nginxListenOn "ethfe" port}

        access_log /var/log/nginx/statshostproxy_access.log;
        error_log /var/log/nginx/statshostproxy_error.log;

        location / {
            resolver ${concatStringsSep " " config.networking.nameservers};
            proxy_pass http://$http_host$request_uri$is_args$args;
        }
      }
    '';

  };
}
