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
