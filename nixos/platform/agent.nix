{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with lib;

let
  cfg = config.flyingcircus;

  # WARNING: path and environment are duplicated in
  # devhost. Unfortunately using references causes conflicts
  # that can not be easily resolved.
  # Path elements needed by both agent units.
  commonEnvPath = with pkgs; [
    bzip2
    gnutar
    gzip
    util-linux
    xz
  ];

  environment = config.nix.envVars // {
    HOME = "/root";
    LANG = "en_US.utf8";
    NIX_PATH = concatStringsSep ":" config.nix.nixPath;
  };
in
{
  options = {
    flyingcircus.agent = {
      install = mkOption {
        default = true;
        description = "Provide the Flying Circus management agent.";
        type = types.bool;
      };

      enable = mkOption {
        default = true;
        description = "Run the Flying Circus management agent automatically.";
        type = types.bool;
      };

      updateInMaintenance = mkOption {
        default = attrByPath [ "parameters" "production" ] false cfg.enc;
        description = "Perform channel updates in scheduled maintenance. Default: all production VMs";
        type = types.bool;
      };

      extraCommands = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Additional commands to execute within an agent run
          after the main NixOS configuration/build has been
          activated.
        '';
      };

      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf (attrsOf (oneOf [ bool int str package ]));
        default = { };
        description = "Additional configuration for fc-agent utilities, will be turned into the contents of /etc/fc-agent.conf";
      };

      verbose = mkOption {
        default = false;
        description = "Enable additional logging for agent debugging.";
        type = types.bool;
      };

      maintenance = mkOption {
        type = with types; attrsOf (submodule {
          options = {
            enter = mkOption { type = str; default = ""; };
            leave = mkOption { type = str; default = ""; };
          };
        });
        default = {};
        description = ''
          Commands that fc.agent will call before entering or leaving
          a maintenance cycle. Those commands must be
          idempotent.
        '';
      };

    };
  };

  config = mkMerge [
    (mkIf cfg.agent.install {
      environment.systemPackages = [ pkgs.fc.agent ];

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [
            "${pkgs.fc.agent}/bin/fc-manage"
            "${pkgs.fc.agent}/bin/fc-maintenance list"
            "${pkgs.fc.agent}/bin/fc-maintenance show"
            "${pkgs.fc.agent}/bin/fc-maintenance delete"
          ];
          groups = [ "sudo-srv" "service" ];
        }
      ];

      environment.etc."fc-agent.conf".text = ''
         [maintenance-enter]
         ${concatStringsSep "\n" (
           mapAttrsToList (k: v: "${k} = ${v.enter}") cfg.agent.maintenance)}

         [maintenance-leave]
         ${concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${v.leave}")
           cfg.agent.maintenance)}
      ''
      + lib.generators.toINI { } cfg.agent.extraSettings;

      systemd.services.fc-agent = rec {
        description = "Flying Circus Management Task";
        wants = [ "network.target" ];
        after = wants;
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutSec = "2h";
          Nice = 18; # 19 is the lowest
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7; #lowest
          IOWeight = 10; # 1-10000
        };

        path = with pkgs; [
          config.system.build.nixos-rebuild
          fc.agent
        ] ++ commonEnvPath;

        inherit environment;

        script =
          let
            verbose = lib.optionalString cfg.agent.verbose "--verbose";
            options = "--enc-path=${cfg.encPath} ${verbose}";
            wrappedExtraCommands = lib.optionalString (cfg.agent.extraCommands != "") ''
              (
              # flyingcircus.agent.extraCommands
              ${cfg.agent.extraCommands}
              ) || rc=$?
            '';
          in ''
            rc=0
            fc-resize-disk || rc=$?
            # Ignore failing attempts at getting ENC data from the directory.
            # This happens sometimes when the directory is overloaded and
            # usually works on the next try.
            fc-manage ${options} update-enc || true
            fc-manage ${options} switch --lazy || rc=$?
            fc-maintenance ${options} request system-properties || rc=$?
            (
              fc-maintenance ${options} schedule
              fc-maintenance ${options} run
            ) || rc=$?
            ${wrappedExtraCommands}
            exit $rc
          '';
      };

      # This was a part of the fc-agent service earlier.
      # They use shared code paths but they won't run at the same
      # time because there's an exclusive lock file for actions that
      # might affect the system.
      systemd.services.fc-update-channel = rec {
        description = "Update system channel";
        wants = [ "network.target" ];
        after = wants;
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          TimeoutSec = "2h";
          Nice = 18; # 19 is the lowest
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7; #lowest
          IOWeight = 10; # 1-10000
          ExecStart =
            let
              verbose = lib.optionalString cfg.agent.verbose "--verbose";
              options = "--enc-path=${cfg.encPath} ${verbose}";
              runNow = lib.optionalString (!cfg.agent.updateInMaintenance) "--run-now";
            in
            "${pkgs.fc.agent}/bin/fc-maintenance ${options} request update ${runNow}";
        };

        path = commonEnvPath;

        inherit environment;
      };

      systemd.tmpfiles.rules = [
        "r! /reboot"
        "f /etc/nixos/local.nix 644"
        "d /root 0711"
        "d /var/log/fc-agent - - - 180d"
        "d /var/spool/maintenance/archive - - - 180d"
        # Remove various obsolete files and directories
        # /var/lib/fc-manage was only used on 15.09.
        # The next three entries can be removed when all 15.09 VMs are gone.
        "r /var/lib/fc-manage/fc-manage.stamp"
        "r /var/lib/fc-manage/stamp-channel-update"
        "r /var/lib/fc-manage"
        # The next 2 entries can be removed when all VMs with versions before 22.05 are gone.
        "r /var/log/fc-agent/fc-maintenance-command-output.log"
        "r /var/log/fc-agent/update-activity-command-output.log"
      ];

      # Remove obsolete `/result` symlink
      system.activationScripts.result-symlink = stringAfter [] ''
        ${pkgs.fc.check-age}/bin/check_age -m -w 3d /result >/dev/null || \
          rm /result
      '';

    })

    (mkIf (cfg.agent.install && cfg.agent.enable) {
      # Do not add the timers if the agent is not enabled. This allows
      # deciding, i.e. for testing environments, that the image should not start
      # the general fc-manage service upon boot, which might fail.
      systemd.timers.fc-agent = {
        description = "Timer for fc-agent";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1m";
          OnUnitInactiveSec = "10m";
          RandomizedDelaySec = "10s";
        };
      };
      systemd.timers.fc-update-channel = {
        description = "Update system channel";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1m";
          OnCalendar = "hourly";
          RandomizedDelaySec = "60m";
          FixedRandomDelay = true;
          Persistent = true;
        };
      };
    })
  ];
}
