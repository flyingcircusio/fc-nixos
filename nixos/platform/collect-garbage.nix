{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with builtins;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
  log = "/var/log/fc-collect-garbage.log";

in {
  options = with lib; {
    flyingcircus.agent = {
      collect-garbage =
        mkEnableOption
        "automatic scanning for Nix store references and garbage collection";
    };
  };

  config = lib.mkMerge [
    {
      environment.etc."userscan/exclude".source = ./collect-garbage-userscan.exclude;
      systemd.tmpfiles.rules = [
        "f ${log}"
      ];
    }

    (lib.mkIf cfg.agent.collect-garbage {

      flyingcircus.services.sensu-client = {
        checks.fc-collect-garbage = {
          notification = "nix-collect-garbage stamp recent";
          command =
            "${pkgs.monitoring-plugins}/bin/check_file_age"
            + " -f ${log} -w 216000 -c 432000";
        };
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          # Use the lowest priority settings we can findto make sure that GC
          # gives way to nearly everything else.
          CPUSchedulingPolicy= "idle";
          CPUWeight = 1;
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7;
          IOWeight = 1;
          Nice = 19;
          # We expect our script to produce error codes from 0 to 3.
          # Ignore them as they are often temporary and the garbage collection
          # runs every day. There's a Sensu check that warns us when garbage collection
          # doesn't work for longer time periods.
          SuccessExitStatus = [ 1 2 3 ];
          TimeoutStartSec = "infinity";
        };
        path = with pkgs; [ fc.userscan nix glibc util-linux ];
        environment = {
          LANG = "en_US.utf8";
          PYTHONUNBUFFERED = "1";
        };
        script = "${config.flyingcircus.agent.package}/bin/fc-collect-garbage";
      };

      systemd.timers.fc-collect-garbage = {
        description = "Timer for fc-collect-garbage";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "00:00:00";
          RandomizedDelaySec = "24h";
        };
      };

    })
  ];
}
