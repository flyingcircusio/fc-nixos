{ config, lib, pkgs, ... }:

let
  cfg = config.flyingcircus;

in
{
  options = {
    flyingcircus.quota.enable = lib.mkEnableOption "FC platform quota support";
  };

  config = lib.mkIf cfg.quota.enable {
    fileSystems."/".options = [ "usrquota" "prjquota" ];

    environment.etc.projects.text = ''
      1:/
    '';

    environment.etc.projid.text = ''
      rootfs:1
    '';

    system.activationScripts.setupXFSQuota = {
      text =
        let
          agent = pkgs.fc.agent;
          msg = "Reboot to activate filesystem quotas";
        in
        # keep the grep expression in sync with that one in fcmanage/resize.py
        with pkgs; ''
          if ! egrep -q ' / .*usrquota,.*prjquota' /proc/self/mounts; then
            if ! ${agent}/bin/list-maintenance | fgrep -q "${msg}";
            then
              ${agent}/bin/scheduled-reboot -c "${msg}"
            fi
          fi
        '';
        deps = [ ];
    };
  };
}
