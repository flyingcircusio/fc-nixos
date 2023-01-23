{ config, pkgs, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus.slurm;
  slurmCfg = config.services.slurm;
  inherit (config) fclib;
  controllerEnabled = config.flyingcircus.roles.slurm-controller.enable;
  nodeEnabled = config.flyingcircus.roles.slurm-node.enable;
  dbdserverEnabled = config.flyingcircus.roles.slurm-dbdserver.enable;
  anyRoleEnabled = controllerEnabled || nodeEnabled || dbdserverEnabled;

  serviceHostName = service: lib.head ( lib.splitString "." service.address );

  controlMachine = serviceHostName (fclib.findOneService "slurm-controller-controller");
  dbdserverService = fclib.findOneService "slurm-dbdserver-dbdserver";
  defaultSlurmNodes = map serviceHostName (fclib.findServices "slurm-node-node");

  inherit (config.flyingcircus) enc;
  params = if enc ? parameters then enc.parameters else {};


  nodeStr = lib.concatStringsSep "," cfg.nodes;

  thisNode = config.networking.hostName;

  # XXX: C&P from upstream slurm to get access to the wrapper.
  wrappedSlurm = pkgs.stdenv.mkDerivation {
    name = "wrappedSlurm";

    builder = pkgs.writeText "builder.sh" ''
      source $stdenv/setup
      mkdir -p $out/bin
      find  ${lib.getBin slurmCfg.package}/bin -type f -executable | while read EXE
      do
        exename="$(basename $EXE)"
        wrappername="$out/bin/$exename"
        cat > "$wrappername" <<EOT
      #!/bin/sh
      if [ -z "$SLURM_CONF" ]
      then
        SLURM_CONF="${slurmCfg.etcSlurm}/slurm.conf" "$EXE" "\$@"
      else
        "$EXE" "\$0"
      fi
      EOT
        chmod +x "$wrappername"
      done

      mkdir -p $out/share
      ln -s ${lib.getBin slurmCfg.package}/share/man $out/share/man
    '';
  };

in
{

  options = with lib; {
    flyingcircus.slurm = {

      clusterName = mkOption {
        type = types.str;
        default = params.resource_group or "default";
        defaultText = lib.mdDoc "*resource group name*";
        description = lib.mdDoc ''
          Name of the cluster. Defaults to the name of the resource group.

          The cluster name is used in various places like state files or accounting
          table names and should normally stay unchanged. Changing this requires
          manual intervention in the state dir or slurmctld will not start anymore!
        '';
      };

      accountingStorageEnforce = mkOption {
        type = with types; nullOr str;
        default = null;
        example = "associations";
        description = lib.mdDoc ''
          This controls what level of association-based enforcement to impose on
          job submissions. Valid options are any combination of associations,
          limits, nojobs, nosteps, qos, safe, and wckeys, or all for all
          things (except nojobs and nosteps, which must be requested as well).
          If limits, qos, or wckeys are set, associations will automatically be
          set.

          By setting associations, no new job is allowed to run unless a
          corresponding association exists in the system. If limits are
          enforced, users can be limited by association to whatever job
          size or run time limits are defined.
        '';
      };

      partitionName = mkOption {
        type = types.str;
        default = "all";
        description = lib.mdDoc ''
          Name of the default partition which includes the machines defined via the `nodes` option.
          Don't use `default` as partition name, it will fail!
        '';
      };

      cpus = mkOption {
        type = types.ints.positive;
        default = params.cores or 1;
        defaultText = lib.mdDoc "*number of VM cores*";
        description = lib.mdDoc ''Number of CPU cores used by a slurm compute node.'';
      };

      realMemory = mkOption {
        type = types.ints.positive;
        default = floor ((params.memory or 1024) * 0.98) - 500;
        defaultText = lib.mdDoc "*98% of physical RAM minus 500 MiB*";
        description = lib.mdDoc ''Memory in MiB used by a slurm compute node.'';
      };

      mungeKeyFile = mkOption {
        internal = true;
        type = types.str;
        default = "/var/lib/munge/munge.key";
      };

      nodes = mkOption {
        type = types.listOf types.str;
        default = defaultSlurmNodes;
        defaultText = lib.mdDoc "*all Slurm nodes in the resource group*";
        description = lib.mdDoc ''
          Names of the nodes that are added to the automatically generated partition.
          By default, all Slurm nodes in a resource group are part of the partition
          called `partitionName`.
        '';
      };

    };

    flyingcircus.roles = {
      slurm-node = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };

      slurm-controller = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };

      slurm-dbdserver = {
        enable = mkEnableOption "";
        supportsContainers = fclib.mkDisableContainerSupport;
      };
    };
  };

  config = lib.mkMerge [

    (lib.mkIf anyRoleEnabled {
      environment.etc.slurm.source = slurmCfg.etcSlurm;

      environment.etc."local/slurm/README.md".text =
        let
          roleStr = lib.concatStringsSep ", "
            (lib.optional controllerEnabled "*controller*" ++
             lib.optional dbdserverEnabled "*dbdserver*" ++
             lib.optional nodeEnabled "*compute node*");
        in
        ''
        # Slurm Workload Manager

        This VM is acting as: slurm ${roleStr}.

        Generated config is at `${slurmCfg.etcSlurm}` which is also linked to `/etc/slurm`.
        You can use `slurm-show-config` to view contents of all config files.

        Cluster name is `${cfg.clusterName}`.

        Our slurm roles work without additional configuration.
        They automatically set up and use a slurm partition named `${cfg.partitionName}`.

        ${if cfg.nodes != [] then ''
        Following nodes are members of the `${cfg.partitionName}` partition:
        `${fclib.docList cfg.nodes}`
        '' else ''
        **Warning**: No nodes are configured! If default config is used, this
        means that no machine with the *slurm-node* role was found in the
        resource group.
        *slurmctld* is disabled on this machine until nodes are added.
        ''}

        ## Slurm commands

        The standard slurm commands like `srun`, `sacct`, `scontrol` and `sinfo` are
        installed globally. Some require elevated privileges and must be run
        with `sudo -u slurm`. `sudo-srv` users can run all commads as `slurm`
        user.

        ${lib.optionalString nodeEnabled ''
        Usable real memory for this node is set to ${toString cfg.realMemory} MiB
        and CPU count is ${toString cfg.cpus}.
        ''}

        ## fc-slurm Global/Controller Commands

        You can use fc-slurm to manage the state of slurm compute nodes
        managed by this controller.

        Commands should be run with sudo.
        `fc-slurm all-nodes state` works as normal user.

        *sudo-srv* users may use `fc-slurm` without password.

        Dump node state info as JSON:

        `fc-slurm all-nodes state`

        Drain all nodes (no new jobs allowed) and set them to DOWN afterwards:

        `sudo fc-slurm all-nodes drain-and-down`

        Mark all nodes as READY:

        `sudo fc-slurm all-nodes ready`

        The `drain` and `ready` commands check if nodes are in an expected
        start state and throw an error if this is not the case, for example
        if they already are in the wanted state.

        Add `--nothing-to-do-is-ok` to ignore the state check.


        ## NixOS Options
        ${fclib.docOption "flyingcircus.slurm.accountingStorageEnforce"}

        ${fclib.docOption "flyingcircus.slurm.nodes"}

        ${fclib.docOption "flyingcircus.slurm.clusterName"}

        ${fclib.docOption "flyingcircus.slurm.partitionName"}

        ${fclib.docOption "flyingcircus.slurm.realMemory"}

        ${fclib.docOption "flyingcircus.slurm.cpus"}

        ${fclib.docOption "services.slurm.extraConfig"}

        ${fclib.docOption "services.slurm.dbdserver.extraConfig"}
      '';

      environment.systemPackages = [
        (pkgs.writeShellScriptBin "slurm-config-dir" "echo ${slurmCfg.etcSlurm}")
        (pkgs.writeShellScriptBin
          "slurm-readme"
          "${pkgs.rich-cli}/bin/rich --pager /etc/local/slurm/README.md"
        )
        (pkgs.writeShellScriptBin "slurm-show-config" ''
          for x in ${slurmCfg.etcSlurm}/*; do
            echo "''${x}:"
            cat $x
          done
        '')
      ];

      flyingcircus.passwordlessSudoRules = [
        {
          commands = [ "ALL" ];
          groups = [ "sudo-srv" ];
          runAs = "slurm";
        }
        {
          commands = [ "${pkgs.fc.agent}/bin/fc-slurm" ];
          groups = [ "sudo-srv" ];
        }
      ];

      services.slurm = {
        inherit (cfg) clusterName;
        inherit controlMachine;
        nodeName = [ "${nodeStr} State=UNKNOWN CPUs=${toString cfg.cpus} RealMemory=${toString cfg.realMemory}" ];
        partitionName = [ "${cfg.partitionName} Nodes=${nodeStr} Default=YES MaxTime=INFINITE State=UP" ];
        extraConfig = ''
          # FCIO extra config
          # XXX: Some settings probably be separate options later.

          # JOB PRIORITY
          PriorityType = priority/multifactor
          PriorityWeightQOS = 2000

          # SCHEDULING
          # Allocate individual processors and memory
          SelectType = select/cons_res
          SelectTypeParameters = CR_CPU_Memory

          # Upon registration with a valid configuration only if it was set
          # DOWN due to being non-responsive.

          ReturnToService = 1

          SlurmctldDebug = info
          SlurmdDebug = info

          # Enables resource containment using sched_setaffinity(). This
          # enables the --cpu-bind and/or --mem-bind srun options.
          TaskPlugin = task/affinity

        '' + (lib.optionalString (dbdserverService != null) ''
          AccountingStorageType = accounting_storage/slurmdbd

          ${lib.optionalString (cfg.accountingStorageEnforce != null)
          "AccountingStorageEnforce = ${cfg.accountingStorageEnforce}"
          }

          # Include the job's comment field in the job complete message sent
          # to the Accounting Storage database.
          AccountingStoreFlags = job_comment
          JobAcctGatherType = jobacct_gather/linux
        '');
      };

      systemd.services.fc-set-munge-key = {
        path = [ pkgs.jq ];
        script = ''
          umask 0266
          mkdir -p $(dirname ${cfg.mungeKeyFile})
          jq -r \
            '.[] | select(.service =="slurm-controller-controller") | .password' \
            /etc/nixos/services.json | sha256sum | head -c64 \
            > ${cfg.mungeKeyFile}

          chown munge:munge ${cfg.mungeKeyFile}
          echo "fc-set-munge-key finished"
        '';

        serviceConfig = {
          Type = "oneshot";
        };
      };

      systemd.services.munged = {
        after = [ "fc-set-munge-key.service" ];
        requires = [ "fc-set-munge-key.service" ];
        serviceConfig = {
          ExecStartPre = lib.mkForce [
            "${pkgs.coreutils}/bin/stat ${cfg.mungeKeyFile}"
          ];
        };
      };

      services.munge.password = cfg.mungeKeyFile;

      users.users.slurm.extraGroups = [ "service" ];
    })

    # We need at least one compute node or the controller will crash on startup.
    (lib.mkIf (controllerEnabled && cfg.nodes != []) {

      flyingcircus.agent.maintenance.slurm-controller = {
        enter = "fc-slurm -v all-nodes drain-and-down --nothing-to-do-is-ok";
        leave = "fc-slurm -v all-nodes ready --nothing-to-do-is-ok";
      };

      services.slurm = {
        server.enable = true;
      };

      systemd.services.slurmctld = {
        serviceConfig = {
          Restart = "always";
        };
      };

    })

    (lib.mkIf (nodeEnabled && !controllerEnabled) {
      flyingcircus.agent.maintenance.slurm-node = {
        enter = "fc-slurm -v drain-and-down --nothing-to-do-is-ok";
      };
    })

    (lib.mkIf nodeEnabled {

      services.slurm = {
        client.enable = true;
      };

      systemd.services.slurmd = {
        after = [ "munged.service" ];
        serviceConfig = {
          Restart = "always";
        };
      };

      systemd.services.fc-agent.environment = {
        SLURM_CONF = "${slurmCfg.etcSlurm}/slurm.conf";
      };


    })

    (lib.mkIf dbdserverEnabled {

      flyingcircus.roles.percona80 = {
        enable = true;
      };

      flyingcircus.roles.mysql.extraConfig = ''
        [mysqld]
        # slurmdbd may refuse to start if we don't increase this setting.
        innodb_lock_wait_timeout = 900
      '';

      systemd.services.fc-slurmdbd-mysql-setup = {
        description = "Ensure slurm accounting user and database exist.";
        documentation = [
          "https://slurm.schedmd.com/accounting.html"
        ];
        partOf = [ "mysql.service" ];
        requiredBy = [ "slurmdbd.service" ];
        after = [ "mysql.service" "fc-mysql-post-init.service" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };

        script = let
          ensureUserAndDatabase = ''
            CREATE USER IF NOT EXISTS slurm@localhost;
            CREATE DATABASE IF NOT EXISTS slurm_acct_db;
            GRANT ALL ON slurm_acct_db.* TO slurm@localhost;
          '';
          mysqlCmd = sql:
            "${config.services.percona.package}/bin/mysql" +
            " --defaults-extra-file=/root/.my.cnf" +
            " -v" +
            " -e '${sql}'";
        in
        "${mysqlCmd ensureUserAndDatabase}";
      };

      services.slurm.dbdserver = {
        enable = true;
      };
    })
  ];
}
