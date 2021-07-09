{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_osd;
  enc = config.flyingcircus.enc;

in
{
  options = {
    flyingcircus.roles.ceph_osd = {
      enable = lib.mkEnableOption "CEPH OSD";

      # This option can be used to disable automatic reactivation, e.g.
      # if you're working on a system and don't want to get (slow) reloads 
      # blocking agent runs all the time.
      reactivate = lib.mkOption {
        default = true;
        description = "Reload OSDs during agent run.";
        type = lib.types.bool;
       };
    };
  };

  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.server.enable = true;

    systemd.services.fc-ceph-osds = rec {
      description = "Start/stop local Ceph OSDs (via fc-ceph)";
      wantedBy = [ "multi-user.target" ];
      # Ceph requires the IPs to be properly attached to interfaces so it
      # knows where to bind to the public and cluster networks.
      wants = [ "network.target" ];
      after = wants;

      environment = {
        PYTHONUNBUFFERED = "1";
      };

      restartIfChanged = false;
      reloadIfChanged = true;
      restartTriggers = [
        config.environment.etc."ceph/ceph.conf".source
        pkgs.ceph
      ];

      script = ''
          ${pkgs.fc.ceph}/bin/fc-ceph osd activate all
      '';

      reload = lib.optionalString role.reactivate ''
          ${pkgs.fc.ceph}/bin/fc-ceph osd reactivate all
      '';

      preStop = ''
         ${pkgs.fc.ceph}/bin/fc-ceph osd deactivate all
      '';

      serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
      };
    };

  };
}
