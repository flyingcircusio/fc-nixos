{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  listenAddresses =
    fclib.listenAddresses "lo" ++
    fclib.listenAddresses "ethsrv";

in
{
  options = {
    flyingcircus.roles.antivirus = {
      enable = lib.mkEnableOption "ClamAV antivirus scanner";
    };
  };

  config = lib.mkIf config.flyingcircus.roles.antivirus.enable {
    services.clamav.daemon = {
      enable = true;
      extraConfig = ''
        TCPSocket 3310
      '' + lib.concatMapStringsSep "\n" (ip: "TCPAddr ${ip}") listenAddresses;

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
            check_file_age -w 86400 -c 172800 /var/lib/clamav/mirrors.dat
          '';
          interval = 300;
          };

        clamav-listen = {
          notification = "clamd not reachable via TCP";
          command = ''
            ${pkgs.sensu-plugins-network-checks}/bin/check-ports.rb \
              -h ${lib.concatStringsSep "," listenAddresses} -p 3310
          '';
        };

      };
    };
  };
}
