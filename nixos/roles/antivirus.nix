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

    services.clamav.updater.enable = true;

    systemd.services.clamav-freshclam.serviceConfig = {
      # We monitor systemd process status for alerting, but this really
      # isn't critical to wake up people. We'll catch errors when the
      # file age check for the database update goes critical.
      # The list is taken from the freshclam manpage.
      SuccessExitStatus = lib.mkForce [ 40 50 51 52 53 54 55 56 57 58 59 60 61 62 ];
    };

    flyingcircus.services = {
      sensu-client.checks = {

        clamav-updater = {
          notification = "ClamAV virus database up-to-date";
          command = ''
            check_file_age -w 86400 -c 172800 /var/lib/clamav/daily.cld
          '';
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
