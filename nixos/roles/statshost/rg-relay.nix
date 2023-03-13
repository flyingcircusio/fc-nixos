# Relay stats of a resource group via NGINX.
# TODO: rename, the role name should say that it's acting as a resource group proxy.
{ config, lib, pkgs, ... }:

with lib;

{
  config = mkIf config.flyingcircus.roles.statshost-relay.enable {

    flyingcircus.services.nginx.enable = true;
    services.nginx.appendHttpConfig = ''
      server {
        listen ${config.services.prometheus.listenAddress};
        access_log /var/log/nginx/statshost-relay_access.log;
        error_log /var/log/nginx/statshost-relay_error.log;

        location = /scrapeconfig.json {
          alias /etc/local/statshost/scrape-rg.json;
        }

        location / {
            resolver ${concatStringsSep " " config.networking.nameservers};
            proxy_pass http://$host:9126$request_uri$is_args$args;
            limit_except GET { deny all; }
        }
      }
    '';

  };
}
