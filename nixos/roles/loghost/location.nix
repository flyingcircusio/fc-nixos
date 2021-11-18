{ config, lib, pkgs, ... }:

let
  cfg = config.flyingcircus.roles.loghost-location;
  fclib = config.fclib;

in
{

  options = {

    flyingcircus.roles.loghost-location = {

      enable = lib.mkEnableOption ''
        Flying Circus central Loghost role.

        This role enables the full graylog stack at once (GL, ES, Mongo).

        Used for location-central log hosts that aggregate system logs from
        all systems in that location.
      '';

      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkIf (cfg.enable) {

    flyingcircus.roles.loghost = fclib.mkPlatform { enable = true; };
    flyingcircus.roles.graylog = {
      serviceTypes = fclib.mkPlatform [ "loghost-location-graylog" ];
    };

  };

}
