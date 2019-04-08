{ config, lib, ... }:

with lib;
{
  options = {

    flyingcircus.roles.webgateway.enable =
      mkEnableOption "FC web gateway role (nginx/haproxy)";

  };

  config = mkIf config.flyingcircus.roles.webgateway.enable {
    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.haproxy.enable = true;
  };
}
