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
        default = attrByPath [ "parameters" "production" ] false cfg.enc;
        description = "Perform channel updates in scheduled maintenance. Default: all production VMs";
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

      extraCommands = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Additional commands to execute within an agent run
          after the main NixOS configuration/build has been 
          activated.
        '';
      };

      interval = mkOption {
        type = types.int;
        default = 60;
        description = "Run channel updates every N minutes.";
      };

    };
  };

  config = mkMerge [
    (mkIf cfg.agent.install {
      environment.systemPackages = [ pkgs.fc.agent ];

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ "${pkgs.fc.agent}/bin/fc-manage" ];
          groups = [ "sudo-srv" "service" ];
        }
      ];

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
          bzip2
          config.system.build.nixos-rebuild
          fc.agent
          gnutar
          gzip
          utillinux
          xz
        ];

        environment = config.nix.envVars // {
          HOME = "/root";
          LANG = "en_US.utf8";
          NIX_PATH = concatStringsSep ":" config.nix.nixPath;
        };

        script =
          let interval = toString cfg.agent.interval;
          in ''
            rc=0
            timeout 14400 ionice -c3 \
              fc-manage -E ${cfg.encPath} -i ${interval} \
              ${cfg.agent.steps} || rc=$?
            timeout 900 fc-resize -E ${cfg.encPath} || rc=$?
            ${cfg.agent.extraCommands}
            exit $rc
          '';
      };

      systemd.tmpfiles.rules = [
        "r! /reboot"
        "f /etc/nixos/local.nix 644"
        "d /root 0711"
        "d /var/lib/fc-manage"
        "r /var/lib/fc-manage/stamp-channel-update"
        "d /var/spool/maintenance/archive - - - 180d"
      ];

      # Remove obsolete `/result` symlink
      system.activationScripts.result-symlink = stringAfter [] ''
        ${pkgs.fc.check-age}/bin/check_age -m -w 3d /result >/dev/null || \
          rm /result
      '';

    })

    (mkIf (cfg.agent.install && cfg.agent.enable) {
      # Do not include the service if the agent is not enabled. This allows
      # deciding, i.e. for Vagrant, that the image should not start the
      # general fc-manage service upon boot, which might fail.
      systemd.timers.fc-agent = {
        description = "Timer for fc-agent";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnActiveSec = "1m";
          OnUnitInactiveSec = "10m";
          RandomizedDelaySec = "10s";
        };
      };
    })
  ];
}
