# This node runs service checks as defined in directory.
# Requires ring 0 access.
{ config, lib, pkgs, ...}:

let
  cfg = config.flyingcircus.roles.servicecheck;
in
{

  options = with lib; {
    flyingcircus.roles.servicecheck = {
      enable = mkEnableOption "Enable the Flying Circus Service Check role.";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.services.fc-servicecheck = {
      description = "Flying Circus global Service Checks";
      # Run this *before* fc-manage rebuilds the system. This service loads
      # off the sensu configuration for nixos to pick it up.
      wantedBy = [ "fc-manage.service" ];
      before = [ "fc-manage.service" ];
      wants = [ "network.target" ];
      after = [ "network.target" ];
      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      serviceConfig = {
        ProtectHome = true;
        ProtectSystem = true;
        User = "root";
        Type = "oneshot";
      };

      script = ''
        ${pkgs.fc.agent}/bin/fc-monitor --enc ${config.flyingcircus.encPath} configure-checks
      '';
    };

  };

}
