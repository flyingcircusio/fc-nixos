{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_osd;
  enc = config.flyingcircus.enc;

  ceph_sudo = pkgs.writeScriptBin "ceph-sudo" ''
    #! ${pkgs.stdenv.shell} -e
    exec /run/wrappers/bin/sudo ${pkgs.ceph}/bin/ceph "$@" 
  '';
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

    systemd.services.fc-ceph-osds = {
      description = "Start/stop local Ceph OSDs (via fc-ceph)";
      wantedBy = [ "multi-user.target" ];

      # Wrap fc-ceph properly
      path = [ pkgs.lvm2 pkgs.ceph pkgs.utillinux ];

      environment = {
        PYTHONUNBUFFERED = "1";
      };

      restartIfChanged = false;
      reloadIfChanged = true;
      restartTriggers = [
        (pkgs.writeText "ceph.conf" config.environment.etc."ceph/ceph.conf".text)
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
