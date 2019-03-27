{ config, lib, pkgs, ... }:

# Our management agent keeping the system up to date, configuring it based on
# changes to our nixpkgs clone and data from our directory

with lib;

let
  cfg = config.flyingcircus;

  channelAction =
    if cfg.agent.with-maintenance
    then "--channel-with-maintenance"
    else "--channel";

in {
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

      with-maintenance = mkOption {
        default = false;
        description = "Perform channel updates in scheduled maintenance.";
        type = types.bool;
      };

      steps = mkOption {
        type = types.str;
        default = "${channelAction} --automatic --directory --system-state \\
          --maintenance";
        description = ''
          Steps to run by the agent (besides channel with/without maintenance
          action).
        '';
      };

      interval = mkOption {
        type = types.int;
        default = 120;
        description = "Run channel updates every N minutes.";
      };

    };
  };

  config = mkMerge [
    (mkIf cfg.agent.install {
      environment.systemPackages = [ pkgs.fc.agent ];

      systemd.services.fc-agent = rec {
        description = "Flying Circus Management Task";
        enable = cfg.agent.enable;
        wants = [ "network.target" ];
        after = wants;
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          # don't kill a running fc-manage instance when switching to
          # enable=false
          KillMode = "none";
          # TimeoutSec won't work because of KillMode. The script uses 'timeout'
          # instead.
        };

        path = with pkgs; [
          fc.agent
          config.system.build.nixos-rebuild
        ];

        environment = config.nix.envVars // {
          HOME = "/root";
          LANG = "en_US.utf8";
          NIX_PATH = concatStringsSep ":" config.nix.nixPath;
        };

        script =
          let interval = toString cfg.agent.interval;
          in ''
            timeout 14400 fc-manage -E ${cfg.encPath} -i ${interval} ${cfg.agent.steps}
            timeout 900 fc-resize -E ${cfg.encPath}
          '';
      };

      systemd.tmpfiles.rules = [
        "r! /reboot"
        "f /etc/nixos/local.nix 644"
        "d /var/lib/fc-manage"
        "r /var/lib/fc-manage/stamp-channel-update"
        "d /var/spool/maintenance/archive - - - 90d"
      ];

      security.sudo.extraRules = [
        {
          commands = [ "${pkgs.fc.agent}/bin/fc-manage" ];
          groups = [ "sudo-srv" "service" ];
        }
      ];
    })

    (mkIf (cfg.agent.install && cfg.agent.enable) {
      # Do not include the service if the agent is not enabled. This allows
      # deciding, i.e. for Vagrant, that the image should not start the
      # general fc-manage service upon boot, which might fail.
      systemd.timers.fc-agent = {
        description = "Timer for fc-agent";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          AccuracySec = "1us";
          OnStartupSec = "10s";
          OnUnitInactiveSec = "10m";
          RandomizedDelaySec = "10s";
        };
      };
    })
  ];
}
