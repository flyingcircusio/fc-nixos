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

      extraSettings = lib.mkOption {
        type = with lib.types; attrsOf (attrsOf (oneOf [ bool int str package ]));
        default = { };
        description = "Additional configuration for fc-agent utilities, will be turned into the contents of /etc/fc-agent.conf";
      };

      interval = mkOption {
        type = types.int;
        default = 60;
        description = "Run channel updates every N minutes.";
      };

      lazySwitch = mkOption {
        default = true;
        description = ''
          Only switch to the new configuration if the system has actually
          changed.
        '';
        type = types.bool;
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
          commands = [ "${pkgs.fc.agent}/bin/fc-manage" ];
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
          Nice = 18; # 19 is the lowest
          IOSchedulingClass = "idle";
          IOSchedulingPriority = 7; #lowest
          IOWeight = 10; # 1-10000
        };

         # WARNING: path and environment are duplicated in
         # devhost. Unfortunately using references causes conflicts
         # that can not be easily resolved.
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
          let
            interval = toString cfg.agent.interval;
            lazy = lib.optionalString cfg.agent.lazySwitch "-l";
            verbose = lib.optionalString cfg.agent.verbose "-v";
          in ''
            rc=0
            timeout 14400 \
              fc-manage -E ${cfg.encPath} -i ${interval} \
              ${lazy} ${verbose} ${cfg.agent.steps} || rc=$?
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
        "d /var/log/fc-agent - - - 180d"
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
    })
  ];
}
