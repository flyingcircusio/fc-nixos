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

  # ulimits in nix-build context are a bit hairy: root needs those both in
  # interactive environments and units that interact with nix, whereas
  # regular users will rely on the the ulimits set for the nix-daemon.
  nixBuildMEMLOCK = "1073741824";
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

      package = mkOption {
        type = types.package;
        example = literalExpression "pkgs.fc.agentWithSlurm";
        default = pkgs.fc.agent;
        defaultText = "pkgs.fc.agent";
        description = lib.mdDoc ''
          agent package to use.
        '';
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

      resizeDisk = mkOption {
        default = (attrByPath [ "parameters" "machine" ] "virtual" cfg.enc) == "virtual";
        description = ''
          Automatically resize root disk when the underlying device changes.
          Enabled for all virtual machines by default.
        '';
        type = types.bool;
      };

      updateInMaintenance = mkOption {
        default = true;
        description = ''
          Perform channel updates in scheduled maintenance. If set to false,
          machines switch to new channels immediately, without running
          maintenance enter and exit commands.
          '';
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

      extraPreCommands = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Additional commands to execute within an agent run
          before doing anything else.
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

      diskKeepFree = mkOption {
        default = 5;
        type = types.numbers.positive;
        description = ''
          Amount of disk space (GiB) to keep free when preparing system updates.

          Updates are refused when less than this value plus the current system size
          is available. The `fc-agent` Sensu check will also become critical.

          The sensu check issues a warning when less than this value plus
          double the current system size is available.

          Example: current system closure size is 2.5 GiB, so at least 7.5 GiB
          have to be available for the update preparation to start.
          The Sensu check will warn if less than 10 GiB are available.
        '';
      };

      maintenanceRequestRunnableFor = mkOption {
        default = 1800;
        # XXX: Ideally, this option would use the max value when set from multiple
        # places but there's no type for that right now. We could implement
        # one if we use this option more often to avoid conflicts.
        type = types.ints.positive;
        description = ''
          Maintenance request are scheduled for a certain time by the directory
          but the local agent may delay execution a bit.
          Requests will be postponed if they had to wait for too long and
          they are "overdue", which is: planned execution time plus the
          value of this option, in seconds.
          By default, there's a window of 30 minutes in which the request
          may be executed.
        '';
      };

      maintenancePreparationSeconds = mkOption {
        default = 300;
        # XXX: Ideally, this option would use the max value when set from multiple
        # places but there's no type for that right now. We could implement
        # one if we use this option more often to avoid conflicts.
        type = types.ints.positive;
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
        cfg.agent.package
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
              "${cfg.agent.package}/bin/fc-maintenance constraints"
              + (lib.concatMapStrings (u: " --in-service ${u}") machines);
        };

      flyingcircus.passwordlessSudoPackages = [
        {
          commands = [
            "bin/fc-collect-garbage"
            "bin/fc-manage"
            "bin/fc-maintenance delete"
            "bin/fc-maintenance -v delete"
          ];
          package = cfg.agent.package;
          groups = [ "admins" "sudo-srv" "service" ];
        }
        {
          commands = [
            "bin/fc-maintenance request reboot"
          ];
          package = cfg.agent.package;
          groups = [ "admins" ];
        }
        {
          commands = [ "bin/fc-manage check" ];
          package = cfg.agent.package;
          users = [ "sensuclient" ];
        }
        {
          commands = [
            "bin/fc-maintenance metrics"
          ];
          package = cfg.agent.package;
          groups = [ "telegraf" ];
        }
        {
          commands = [ "bin/fc-postgresql check-autoupgrade-unexpected-dbs" ];
          package = cfg.agent.package;
          users = [ "sensuclient" ];
          runAs = "postgres";
        }
        {
          commands = [
            "bin/fc-maintenance run"
            "bin/fc-maintenance run --run-all-now"
            "bin/fc-maintenance schedule"
            "bin/fc-maintenance -v run"
            "bin/fc-maintenance -v run --run-all-now"
            "bin/fc-maintenance -v schedule"
          ];
          package = cfg.agent.package;
          groups = [ "admins" ];
        }
      ];

      security.pam.loginLimits = [
        { domain = "root";
          item = "memlock";
          type = "-";
          value = nixBuildMEMLOCK;
        }
      ];

      environment.etc."fc-agent.conf".text = ''
         [limits]
         disk_keep_free = ${toString cfg.agent.diskKeepFree}

         [maintenance]
         preparation_seconds = ${toString cfg.agent.maintenancePreparationSeconds}
         request_runnable_for_seconds = ${toString cfg.agent.maintenanceRequestRunnableFor}

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
          LimitMEMLOCK = nixBuildMEMLOCK;
        };

        path = with pkgs; [
          config.system.build.nixos-rebuild
          cfg.agent.package
        ] ++ commonEnvPath;

        inherit environment;

        script =
          let
            verbose = lib.optionalString cfg.agent.verbose "--show-caller-info";
            options = "--enc-path=${cfg.encPath} ${verbose}";
            wrappedExtraPreCommands = lib.optionalString (cfg.agent.extraPreCommands != "") ''
              (
              # flyingcircus.agent.extraPreCommands
              ${cfg.agent.extraPreCommands}
              ) || rc=$?
            '';
            wrappedExtraCommands = lib.optionalString (cfg.agent.extraCommands != "") ''
              (
              # flyingcircus.agent.extraCommands
              ${cfg.agent.extraCommands}
              ) || rc=$?
            '';
          in ''
            rc=0
            ${wrappedExtraPreCommands}
            ${lib.optionalString cfg.agent.resizeDisk "fc-resize-disk || rc=$?"}
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
              then "${cfg.agent.package}/bin/fc-maintenance ${options} request update"
              else "${cfg.agent.package}/bin/fc-manage ${options} switch --update-channel --lazy";
        };

        path = commonEnvPath;

        inherit environment;
      };

      systemd.services.nix-daemon.serviceConfig.LimitMEMLOCK = nixBuildMEMLOCK;

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
            command = "sudo ${cfg.agent.package}/bin/fc-manage check";
            interval = 300;
          };
          fc-maintenance = {
            notification = "fc-maintenance check failed.";
            command = "${cfg.agent.package}/bin/fc-maintenance check";
            interval = 180;
          };
        };
      };
      flyingcircus.services.telegraf.inputs = {
        exec = [{
          commands = [ "${cfg.agent.package}/bin/fc-maintenance metrics" ];
          timeout = "10s";
          data_format = "json";
          json_name_key = "name";
          interval = "60s";
        }];
      };


    }
  ];
}
