{ config, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.webgateway;
  k3sServer = fclib.findOneService "k3s-server-server";
  fclib = config.fclib;
in
{
  options = {

    flyingcircus.roles.webgateway = with lib; {
      enable = mkEnableOption "FC web gateway role (nginx/haproxy)";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = lib.mkIf cfg.enable {
    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.haproxy.enable = true;
    flyingcircus.services.k3s-frontend.enable = k3sServer != null;
  };

}
