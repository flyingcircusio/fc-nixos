{ config, lib, ... }:

with lib;
let
  fclib = config.fclib;
in
{
  options = {

    flyingcircus.roles.webgateway = {
      enable = mkEnableOption "FC web gateway role (nginx/haproxy)";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = mkIf config.flyingcircus.roles.webgateway.enable {
    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.haproxy.enable = true;
  };
}
