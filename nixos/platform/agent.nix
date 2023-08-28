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

  agentZshCompletions = pkgs.writeText "agent-zsh-completions" ''
    #compdef fc-manage

    _fc_manage_completion() {
      eval $(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _FC_MANAGE_COMPLETE=complete_zsh fc-manage)
    }

    compdef _fc_manage_completion fc-manage


    #compdef fc-maintenance

    _fc_maintenance_completion() {
      eval $(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _FC_MAINTENANCE_COMPLETE=complete_zsh fc-maintenance)
    }

    compdef _fc_maintenance_completion fc-maintenance


    #compdef fc-slurm

    _fc_slurm_completion() {
      eval $(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _FC_SLURM_COMPLETE=complete_zsh fc-slurm)
    }

    compdef _fc_slurm_completion fc-slurm

    #compdef fc-kubernetes

    _fc_kubernetes_completion() {
      eval $(env _TYPER_COMPLETE_ARGS="''${words[1,$CURRENT]}" _FC_KUBERNETES_COMPLETE=complete_zsh fc-kubernetes)
    }

    compdef _fc_kubernetes_completion fc-kubernetes
  '';

  agentZshCompletionsPkg = pkgs.runCommand "agent-zshcomplete" {} ''
    mkdir -p $out/share/zsh/site-functions
    cp ${agentZshCompletions} $out/share/zsh/site-functions/_fc_agent
  '';


  environment = config.nix.envVars // {
    HOME = "/root";
    LANG = "en_US.utf8";
    NIX_PATH = concatStringsSep ":" config.nix.nixPath;
  };

  logDaysKeep = 180;
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

      maintenanceConstraints = {
        machinesInService = mkOption {
          default = [];
          type = with types; listOf str;
          description = ''
            Machines that must not be in maintenance mode at the same time.
            After entering maintenance mode, the agent will check if a listed
            machine is also in maintenance and leave maintenance if it finds
            one. Due maintenance activities will be postponed in that case.
            The name of the current machine is ignored here so you can use the same
            value for this option on all affected machines.
          '';
        };
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

      maintenancePreparationSeconds = mkOption {
        default = 300;
        description = ''
          Expected time in seconds needed to prepare for the execution of
          maintenance activities. The value should cover typical cases where
          maintenance-enter commands have to do extra work or wait for some
          condition to be true. These commands should typically not take
          longer than 5 minutes in total which is the default here.

          If commands are expected to take longer and it's not feasible to
          pause them after 5 minutes and continue later (using TEMPFAIL), the
          preparation time can be increased as needed.

          Currently, the directory doesn't know about "preparation time" as a
          separate concept, so this value is just added to the estimated run
          time for each activity. This overestimates the actual preparation
          time if multiple activities are scheduled continuously because
          maintenance-enter commands are just run once for all runnable
          activities.

          We don't enforce it at the moment but will probably add a timeout
          for maintenance-enter commands later based on this value.
        '';
        type = types.ints.positive;
      };

    };
  };

  config = mkMerge [
    {
      # Write NixOS warnings to a file, separated by two newlines.
      # We use that for `fc-manage check` to display (deprecation) warnings.
      environment.etc."fcio_nixos_warnings".text =
        lib.optionalString (config.warnings != [])
          ((lib.concatStringsSep "\n\n" config.warnings) + "\n");
    }

    (mkIf cfg.agent.install {
      environment.systemPackages = [
        pkgs.fc.agent
        agentZshCompletionsPkg
      ];

      flyingcircus.agent.maintenance =
      let
        machines =
          filter
            (m: m != config.networking.hostName)
            cfg.agent.maintenanceConstraints.machinesInService;
      in
        lib.optionalAttrs (machines != []) {
          other-machines-not-in-maintenance.enter =
              "${pkgs.fc.agent}/bin/fc-maintenance constraints"
              + (lib.concatMapStrings (u: " --in-service ${u}") machines);
        };

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [
            "/run/current-system/sw/bin/fc-collect-garbage"
            "/run/current-system/sw/bin/fc-manage"
            "/run/current-system/sw/bin/fc-maintenance delete"
            "/run/current-system/sw/bin/fc-maintenance -v delete"
          ];
          groups = [ "admins" "sudo-srv" "service" ];
        }
        {
          commands = [ "${pkgs.fc.agent}/bin/fc-manage check" ];
          users = [ "sensuclient" ];
        }
        {
          commands = [ "${pkgs.fc.agent}/bin/fc-postgresql check-autoupgrade-unexpected-dbs" ];
          users = [ "sensuclient" ];
          runAs = "postgres";
        }
        {
          commands = [
            "/run/current-system/sw/bin/fc-maintenance run"
            "/run/current-system/sw/bin/fc-maintenance run --run-all-now"
            "/run/current-system/sw/bin/fc-maintenance schedule"
            "/run/current-system/sw/bin/fc-maintenance -v run"
            "/run/current-system/sw/bin/fc-maintenance -v run --run-all-now"
            "/run/current-system/sw/bin/fc-maintenance -v schedule"
          ];
          groups = [ "admins" ];
        }
      ];

      environment.etc."fc-agent.conf".text = ''
         [maintenance]
         preparation_seconds = ${toString cfg.agent.maintenancePreparationSeconds}

         [maintenance-enter]
         ${concatStringsSep "\n" (
           mapAttrsToList (k: v: "${k} = ${v.enter}") cfg.agent.maintenance)}

         [maintenance-leave]
         ${concatStringsSep "\n" (mapAttrsToList (k: v: "${k} = ${v.leave}")
           cfg.agent.maintenance)}
      '';

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
            verbose = lib.optionalString cfg.agent.verbose "--show-caller-info";
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
              verbose = lib.optionalString cfg.agent.verbose "--show-caller-info";
              options = "--enc-path=${cfg.encPath} ${verbose}";
            in
              if cfg.agent.updateInMaintenance
              then "${pkgs.fc.agent}/bin/fc-maintenance ${options} request update"
              else "${pkgs.fc.agent}/bin/fc-manage ${options} switch --update-channel --lazy";
        };

        path = commonEnvPath;

        inherit environment;
      };

      systemd.tmpfiles.rules = [
        "r! /reboot"
        "f /etc/nixos/local.nix 644"
        "d /root 0711"
        "d /var/log/fc-agent - - - ${toString logDaysKeep}d"
        "d /var/spool/maintenance/archive - - - ${toString logDaysKeep}d"
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

      # Expiring the content of /var/log/fc-agent/ is taken care of by a systemd-tmpfiles
      # rule, no logrotate rule needed
      services.logrotate.settings = {
        "/var/log/fc-agent.log" = {
          # `builtins.ceil` is only available in Nix 2.4+ <=> NixOS 22.05+, blocking
          # updates from 21.11. The alternative, integer division, implicitly applies a
          # `floor`. With the current logDaysKeep = 180, this does not make any difference anyways.
          rotate = if (builtins ? ceil)
            then builtins.ceil (logDaysKeep / (30 + 0.0))  # enforce floating point division
            else (logDaysKeep / 30);
          frequency = "monthly";
        };
      };
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

        unitConfig = {
          # This prevents the timer from activating before the first
          # successful agent run finishes. The initial run takes care of
          # updating the channel initially, without scheduling maintenance.
          # The condition has no effect if the timer is already active.
          ConditionPathExists = "!/etc/nixos/fc_agent_initial_run";
        };

        timerConfig = {
          OnActiveSec = "1m";
          OnCalendar = "hourly";
          RandomizedDelaySec = "60m";
          FixedRandomDelay = true;
          Persistent = true;
        };
      };
    })

    {

      flyingcircus.services.sensu-client = {
        checks = {
          fc-agent = {
            notification = "fc-manage check failed. System may not build and update correctly.";
            command = "sudo ${pkgs.fc.agent}/bin/fc-manage check";
            interval = 300;
          };
          fc-maintenance = {
            notification = "fc-maintenance check failed.";
            command = "${pkgs.fc.agent}/bin/fc-maintenance check";
            interval = 180;
          };
        };
      };
      flyingcircus.services.telegraf.inputs = {
        exec = [{
          commands = [ "${pkgs.fc.agent}/bin/fc-maintenance metrics" ];
          timeout = "10s";
          data_format = "json";
          json_name_key = "name";
          interval = "60s";
        }];
      };


    }
  ];
}
