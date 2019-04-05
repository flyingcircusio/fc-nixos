# Relay stats of a resource group via NGINX
{ config, lib, pkgs, ... }:
with lib;
{
  config = mkIf config.flyingcircus.roles.statshost-relay.enable {

    # XXX use upstream nginx service instead
    # flyingcircus.roles.nginx.enable = true;
    # flyingcircus.roles.nginx.httpConfig = ''
    #   server {
    #     listen ${config.services.prometheus.listenAddress};
    #     access_log /var/log/nginx/loghost_access.log;
    #     error_log /var/log/nginx/loghost_error.log;

    #     location = /scrapeconfig.json {
    #       alias /etc/local/statshost/scrape-rg.json;
    #     }

    #     location / {
    #         resolver ${concatStringsSep " " config.networking.nameservers};
    #         proxy_pass http://$http_host$request_uri$is_args$args;
    #     }
    #   }
    # '';

  };
}
