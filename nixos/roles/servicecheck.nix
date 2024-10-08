# This node runs service checks as defined in directory.
# Requires ring 0 access.
{ config, lib, pkgs, ...}:

let
  cfg = config.flyingcircus.roles.servicecheck;
  fclib = config.fclib;

  # we need check_http_service from fc-sensuplugins, however this
  # package contains commands which collide with monitoring-plugins,
  # so extract check_http_service into a separate package first.
  envPackage = pkgs.linkFarm "fc-sensuplugins-check_http_service" [
    {
      name = "bin/check_http_service";
      path = "${pkgs.fc.sensuplugins}/bin/check_http_service" ;
    }
  ];
in
{

  options = with lib; {
    flyingcircus.roles.servicecheck = {
      enable = mkEnableOption "Enable the Flying Circus Service Check role.";
      supportsContainers = fclib.mkDisableDevhostSupport;
    };
  };

  config = lib.mkIf cfg.enable {

    flyingcircus.services.sensu-client.checks.servicecheck_sensu_config = {
      notification = "Servicecheck sensu config file is not up-to-date.";
      command = ''
        ${pkgs.fc.check-age}/bin/check_age \
          -m /etc/local/sensu-client/directory_servicechecks.json -w 30m -c 2h
      '';
      interval = 300;
    };

    flyingcircus.services.sensu-client.checkEnvPackages = [ envPackage ];

    systemd.services.fc-servicecheck = {
      description = "Flying Circus global Service Checks";
      # Run this *before* fc-manage rebuilds the system. This service loads
      # off the sensu configuration for nixos to pick it up.
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ProtectHome = true;
        ProtectSystem = true;
        User = "root";
        Type = "oneshot";
      };

      script = ''
        ${config.flyingcircus.agent.package}/bin/fc-monitor --enc ${config.flyingcircus.encPath} configure-checks
      '';
    };

    systemd.timers.fc-servicecheck = {
      description = "Update service checks";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnActiveSec = "1m";
        OnUnitInactiveSec = "10m";
        RandomizedDelaySec = "10s";
      };
    };
  };

}
