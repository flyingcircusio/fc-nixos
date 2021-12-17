{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.sensuserver;
  fclib = config.fclib;
in
{

  options = with lib; {

      flyingcircus.roles.sensuserver = {

          enable = mkOption {
              type = types.bool;
              default = false;
              description = "Enable the Flying Circus sensu server role.";
          };
          supportsContainers = fclib.mkDisableContainerSupport;

          hostName = mkOption {
            type = types.str;
            default = "sensu.${config.flyingcircus.enc.parameters.location}.gocept.net";
          };
      };

  };

  config = lib.mkIf config.flyingcircus.roles.sensuserver.enable {

      # Sensu talks to all VMs in a location permanently, so there are
      # a lot of entries in the neighbour table. Increase numbers
      # to avoid unneccessary garbage collecting and table overflows.
      boot.kernel.sysctl = {
        "net.ipv4.neigh.default.gc_thresh1" = 1024;
        "net.ipv4.neigh.default.gc_thresh2" = 4096;
        "net.ipv4.neigh.default.gc_thresh3" = 8192;
        "net.ipv6.neigh.default.gc_thresh1" = 1024;
        "net.ipv6.neigh.default.gc_thresh2" = 4096;
        "net.ipv6.neigh.default.gc_thresh3" = 8192;
      };
      flyingcircus.roles.rabbitmq.enable = true;
      flyingcircus.services.nginx.enable = true;
      flyingcircus.services.rabbitmq.listenAddress = lib.mkOverride 90 "::";
      flyingcircus.services.sensu-api.enable = true;
      flyingcircus.services.sensu-server.enable = true;
      flyingcircus.services.uchiwa.enable = true;

      services.redis.enable = true;
      services.postfix.enable = true;

      services.nginx.virtualHosts = {
        "${cfg.hostName}" = {
          forceSSL = true;
          enableACME = true;
          locations = {
            "/" = {
              proxyPass = "http://[::1]:3000";
            };
            # The trailing slashes are important to have nginx
            # strip the leading /api and the API is not vhost
            # compatible, thus needs this removed.
           "/api/" = {
              proxyPass = "http://127.0.0.1:4567/";
            };
          };
        };
      };
  };
}
