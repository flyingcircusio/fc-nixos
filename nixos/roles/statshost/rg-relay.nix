# Relay stats of a resource group via NGINX.
# TODO: rename, the role name should say that it's acting as a resource group proxy.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.flyingcircus.roles.statshost-relay.enable {
    # open ports for incoming logs from specific VMs in other RGs
    networking.firewall.extraCommands =
      let
        enc = config.flyingcircus.enc;
        fclib = config.fclib;
        roleConfig = enc.role_configuration."statshost-relay";
        prometheusHosts = roleConfig.relay_to_details;
        promPort = 9090;

        makeRule =
          addr:
          "${fclib.iptables addr} -A nixos-fw -i ethsrv -s ${addr} -p tcp --dport ${builtins.toString promPort} -j nixos-fw-accept";

        makeHostBlock =
          name: value:
          lib.concatStringsSep "\n" (
            [ "# statshost-relay to \"${name}\"" ] ++ (map makeRule value.addresses)
          );
      in
      lib.concatStringsSep "\n\n" (lib.mapAttrsToList makeHostBlock prometheusHosts);

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
            resolver ${builtins.concatStringsSep " " config.networking.nameservers};
            proxy_pass http://$host:9126$request_uri$is_args$args;
            limit_except GET { deny all; }
        }
      }
    '';
  };
}
