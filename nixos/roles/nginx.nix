{ config, lib, ... }:

with lib;
{
  options = {

    flyingcircus.roles.nginx.enable =
      mkEnableOption "FC nginx role";

  };

  config = mkIf config.flyingcircus.roles.nginx.enable {
    flyingcircus.services.nginx.enable = true;
  };
}
