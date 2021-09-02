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

   flyingcircus.activationScripts.snipeITTOken = ''
     # Only allow root to read/write this file
     umask 066
     ${pkgs.jq}/bin/jq -r  '.parameters.secrets."snipeit/token"' /etc/nixos/enc.json > /etc/disktracker/token
   '';

    systemd = {
      timers.disktracker = {
        description = "Disktracker";
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "6h";
        };
      };
      services.disktracker = {
        description = "Disktracker";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.disktracker}/bin/disktracker";
      };
    };

    services.udev = {
          extraRules = ''
            ENV{DEVTYPE}=="disk", ACTION=="add|remove", RUN+="${pkgs.systemd}/bin/systemctl start disktracker"
          '';
    };
  };
}
