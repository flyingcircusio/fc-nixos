{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.antivirus;
  fclib = config.fclib;
in
{
  options = {
    flyingcircus.roles.antivirus = {

      enable = lib.mkEnableOption "ClamAV antivirus scanner";

      supportsContainers = fclib.mkEnableContainerSupport;

      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = fclib.network.lo.dualstack.addresses ++
                  fclib.network.srv.dualstack.addresses;
      };
    };
  };

  config = lib.mkIf cfg.enable {

    # The update service isn't critical enough to wake up people.
    # We'll catch errors when the file age check for the database update goes critical.
    services.clamav.daemon = {
      enable = true;
      settings = {
        LogTime = true;
        LogClean = true;
        LogVerbose = true;
        ExtendedDetectionInfo = true;
        ExitOnOOM = true;
        TCPSocket = 3310;
        TCPAddr = cfg.listenAddresses;
      };
    };

    systemd.services.clamav-daemon.serviceConfig = {
      PrivateTmp = lib.mkForce "no";
      PrivateNetwork = lib.mkForce "no";
      Restart = "always";
    };

    services.clamav.updater = {
      enable = true;
      settings = {
        PrivateMirror = "https://clamavmirror.fcio.net";
        ScriptedUpdates = false;
      };
    };

    systemd.services.clamav-freshclam.serviceConfig = {
      # Ignore various error cases to avoid breaking fc-manage if the
      # timer fails during the rebuild.
      # The list is mostly taken from the freshclam manpage.
      # We added 11 which is used when rate limiting hits.
      SuccessExitStatus = lib.mkForce [ 11 40 50 51 52 53 54 55 56 57 58 59 60 61 62 ];
    };

    systemd.timers.clamav-freshclam.timerConfig = {
      OnActiveSec = "10";
      # upstream default is to run the timer hourly but in our case too many VMs
      # try to run at the same time. Randomize the timer to run somewhere in the
      # 1 hour window.
      RandomizedDelaySec = "60m";
      FixedRandomDelay = true;
      Persistent = true;
    };

    flyingcircus.services = {
      sensu-client.mutedSystemdUnits = [ "clamav-freshclam.service" ];
      sensu-client.checks = {

        clamav-updater = {
          notification = "ClamAV virus database out-of-date";
          command = "${pkgs.fc.sensuplugins}/bin/check_clamav_database";
          interval = 300;
          };

        clamav-listen = {
          notification = "clamd not reachable via TCP";
          command = ''
            ${pkgs.sensu-plugins-network-checks}/bin/check-ports.rb \
              -h ${lib.concatStringsSep "," cfg.listenAddresses} -p 3310
          '';
        };

      };
    };
  };
}
