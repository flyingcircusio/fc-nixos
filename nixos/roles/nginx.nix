{ config, lib, ... }:

with lib;
let
  fclib = config.fclib;
in
{
  options = {

    flyingcircus.roles.nginx = {
      enable = mkEnableOption "FC nginx role";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = mkIf config.flyingcircus.roles.nginx.enable {
    flyingcircus.services.nginx.enable = true;
  };
}
