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

   flyingcircus.activationScripts.snipeITToken = ''
     # Only allow root to read/write this file
     ( umask 066
       ${pkgs.jq}/bin/jq -r  '.parameters.secrets."snipeit/token"' /etc/nixos/enc.json > /etc/disktracker/token
     )
   '';

    systemd = {
      timers.disktracker = {
        description = "Disktracker";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          # For scrubbing reasons 6h whould be better, but currently the raidcontroller obscures
          # the relevant changes in storage devices
          OnUnitActiveSec = "10m";
        };
      };
      services.disktracker = {
        description = "Disktracker";
        serviceConfig.Type = "oneshot";
        script = "${pkgs.fc.disktracker}/bin/disktracker";
      };
    };

    services.udev.extraRules =
       let
         disktracker-udev-script = pkgs.writeShellScript "disktracker-udev-script" ''
           if systemctl is-active multi-user.target; then
               SECONDS=0;
               sleep 8
               if [ "$SECONDS" -gt "7" ]; then
                   ${pkgs.systemd}/bin/systemctl start disktracker;
               fi
           fi
         '';
       in
      ''
        ENV{DEVTYPE}=="disk", ACTION=="add|remove", RUN+="${disktracker-udev-script}"
      '';
  };
}
