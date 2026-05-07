{
  config,
  lib,
  pkgs,
  ...
}:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with builtins;

let
  cfg = config.flyingcircus;
  fclib = config.fclib;
  log = "/var/log/fc-collect-garbage.log";

in
{
  options = with lib; {
    flyingcircus.agent = {
      collect-garbage = mkEnableOption "automatic scanning for Nix store references and garbage collection";
      userscan-ignore-users = lib.mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = "Users to ignore while scanning for store references.";
      };
    };
  };

  config = lib.mkMerge [
    {
      environment.etc."userscan/exclude".source = ./collect-garbage-userscan.exclude;
      environment.etc."userscan/ignore-users".text = (
        lib.concatStringsSep "\n" config.flyingcircus.agent.userscan-ignore-users
      );
      systemd.tmpfiles.rules = [
        "f ${log}"
      ];

      nix.settings.auto-optimise-store = true;
    }

    (lib.mkIf cfg.agent.collect-garbage {

      flyingcircus.services.sensu-client.checks = {
        fc-collect-garbage = {
          notification = "nix-collect-garbage stamp recent";
          command = "${pkgs.monitoring-plugins}/bin/check_file_age" + " -f ${log} -w 216000 -c 432000";
        };
        fc-collect-garbage-gcroots = {
          notification = "nix-collect-garbage no human user gcroots";
          command = "${config.flyingcircus.agent.package}/bin/fc-collect-garbage-check";
        };
      };

      systemd.services.fc-collect-garbage = {
        description = "Scan users for Nix store references and collect garbage";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          # Use the lowest priority settings we can findto make sure that GC
          # gives way to nearly everything else.
          CPUSchedulingPolicy = "idle";
          CPUWeight = 1;
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7;
          # default weight, may get disk-specific overrides
          IOWeight = 10; # 1-10000
          Nice = 19;
          # We expect our script to produce error codes from 0 to 3.
          # Ignore them as they are often temporary and the garbage collection
          # runs every day. There's a Sensu check that warns us when garbage collection
          # doesn't work for longer time periods.
          SuccessExitStatus = [
            1
            2
            3
          ];
          TimeoutStartSec = "infinity";
        };
        path = with pkgs; [
          fc.userscan
          glibc
          nix
          util-linux
        ];
        environment = {
          LANG = "en_US.utf8";
          PYTHONUNBUFFERED = "1";
        };
        script = ''
          ${config.flyingcircus.agent.package}/bin/fc-collect-garbage
          echo "Optimizing nix store"
          nix-store --optimise
        '';
      };

      systemd.timers.fc-collect-garbage =
        let
          start =
            if lib.hasAttrByPath [ "parameters" "maintenance_allowed_start" ] cfg.enc then
              cfg.enc.parameters.maintenance_allowed_start
            else
              22;
          end =
            if lib.hasAttrByPath [ "parameters" "maintenance_allowed_end" ] cfg.enc then
              cfg.enc.parameters.maintenance_allowed_end
            else
              5;
          maintenanceDuration = if end < start then (end + 24) - start else end - start;
          offsetDuration = fclib.min [
            1
            maintenanceDuration
          ];
        in
        {
          description = "Timer for fc-collect-garbage";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* ${toString start}:00:00";
            RandomizedOffsetSec = "${toString offsetDuration}h";
          };
        };

    })
  ];
}
