{ config, lib, pkgs, ... }:

let
  conf = config.flyingcircus.services.disktracker;
in

with builtins;
{
  options = {
    flyingcircus.services.disktracker = {
      enable = lib.mkEnableOption "Disktracker service";
    };
  };

  config = lib.mkIf conf.enable {
    environment = {
      systemPackages = with pkgs; [ fc.disktracker ];
      etc."disktracker/disktracker.conf".text = ''
         [snipe.it]
         url = https://assets.fcstag.fcio.net
      '';
    };

    # We used to create the admin key directory from the ENC. However,
    # this causes the file to become world readable on servers.

   flyingcircus.activationScripts.snipeITToken = ''
     # Only allow root to read/write this file
     umask 066
     ${pkgs.jq}/bin/jq -r  '.parameters.secrets."snipeit/token"' /etc/nixos/enc.json > /etc/disktracker/token
   '';

    systemd = {
      timers = {
        disktracker = {
          description = "Disktracker";
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "6h";
          };
        };
        disktrackerUdevFlag = {
          description = "Udev flag for Disktracker";
          timerConfig.OnBootSec = "2s";
        };
      };
      services = {
        disktracker = {
          description = "Disktracker";
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = "${pkgs.fc.disktracker}/bin/disktracker";
        };
        disktrackerUdevFlag = {
          description = "Udev flag for Disktracker";
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = "${pkgs.coreutils}/bin/touch /run/disktracker";
        };
      };
    };

    services.udev = {
      extraRules =
         let
           script = pkgs.writeScript "disktracker-udev-script" ''
             #!/bin/sh
             if [ -f "/run/disktracker" ];
               then
               ${pkgs.systemd}/bin/systemctl start disktracker;
             fi
           '';
         in
        ''
          ENV{DEVTYPE}=="disk", ACTION=="add|remove", RUN+="${script}"
        '';
    };
  };
}
