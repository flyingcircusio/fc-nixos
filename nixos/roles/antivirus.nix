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
        defaultText = "addresses of the interfaces `lo` and `srv` (IPv4 & IPv6)";
      };
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [{
      assertion = config.flyingcircus.enc.parameters.memory >= 3072;
      message = "antivirus role: ClamAV needs at least 3GiB of memory to run stable";
    }];

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

    systemd.services.clamav-daemon = {
      serviceConfig = {
        PrivateTmp = lib.mkForce "no";
        PrivateNetwork = lib.mkForce "no";
        Restart = "always";
      };

      unitConfig = {
        # Only start clamav when required database files are present.
        # Taken from the service template from the clamav repo.
        ConditionPathExistsGlob = [
          "/var/lib/clamav/main.{c[vl]d,inc}"
          "/var/lib/clamav/daily.{c[vl]d,inc}"
        ];
      };
    };

    systemd.services.clamav-init-database = {
      # Shouldn't have a dependency on clamav-freshclam to avoid unneccessary
      # starts. For example, using `requires would always trigger freshclam
      # when the daemon (re)starts, causing unwanted startup delays.
      wantedBy = [ "clamav-daemon.service" ];
      before = [ "clamav-daemon.service" ];
      # This is a blocking call so we can be sure that the database
      # has been created before starting the daemon.
      serviceConfig.ExecStart = "systemctl start clamav-freshclam";
      unitConfig = {
        # Opposite condition of clamav-daemon: only run this service if
        # database files are not present.
        ConditionPathExistsGlob = [
          "!/var/lib/clamav/main.{c[vl]d,inc}"
          "!/var/lib/clamav/daily.{c[vl]d,inc}"
        ];
      };
    };

    services.clamav.updater = {
      enable = true;
      settings = {
        PrivateMirror = "https://clamavmirror.fcio.net";
        ScriptedUpdates = false;
      };
    };

    systemd.services.clamav-freshclam = {
      # By using `wants` here, the daemon is started after the freshclam run
      # if the daemon unit is not active yet, probably because of missing
      # database files.
      # nixpkgs already sets `after` in clamav-daemon so the startup order
      # is correct.
      wants = [ "clamav-daemon.service" ];
      serviceConfig = {
        # Ignore various error cases to avoid breaking fc-manage if the
        # timer fails during the rebuild.
        # The list is mostly taken from the freshclam manpage.
        # We added 11 which is used when rate limiting hits.
        SuccessExitStatus = lib.mkForce [ 11 40 50 51 52 53 54 55 56 57 58 59 60 61 62 ];
      };
    };

    systemd.timers.clamav-freshclam.timerConfig = {
      # upstream default is to run the timer hourly but in our case too many VMs
      # try to run at the same time. Randomize the timer to run somewhere in the
      # 1 hour window.
      RandomizedDelaySec = "60m";
      FixedRandomDelay = true;
      Persistent = true;
    };

    flyingcircus.services = {
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
