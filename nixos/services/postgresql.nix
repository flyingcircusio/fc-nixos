{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.postgresql;
  upstreamCfg = config.services.postgresql;
  fclib = config.fclib;
  packages = {
    "11" = pkgs.postgresql_11;
    "12" = pkgs.postgresql_12;
    "13" = pkgs.postgresql_13;
    "14" = pkgs.postgresql_14;
    "15" = pkgs.postgresql_15;
  };

  oldestMajorVersion = head (lib.attrNames packages);

  listenAddresses =
    fclib.network.lo.dualstack.addresses ++
    fclib.network.srv.dualstack.addresses;

  currentMemory = fclib.currentMemory 256;
  sharedMemoryMax = currentMemory / 2 * 1048576;

  sharedBuffers =
    fclib.min [
      (fclib.max [16 (currentMemory / 4)])
      (sharedMemoryMax * 4 / 5)];

  walBuffers =
    fclib.max [
      (fclib.min [64 (sharedBuffers / 32)])
      1];

  workMem = fclib.max [1 (sharedBuffers / 200)];
  maintenanceWorkMem = fclib.max [16 workMem (currentMemory / 20)];

  randomPageCost =
    let rbdPool =
      lib.attrByPath [ "parameters" "rbd_pool" ] null config.flyingcircus.enc;
    in
    if rbdPool == "rbd.ssd" then 1 else 4;

  # using this ugly expression is the only way to get a dynamic path into the
  # Nix store
  localConfigPath = /etc/local/postgresql + "/${cfg.majorVersion}";

  legacyConfigFiles =
    if pathExists localConfigPath
    then filter (lib.hasSuffix ".conf") (fclib.files localConfigPath)
    else [];

  legacyConfigWarning =
    ''Plain PostgreSQL configuration found in ${toString localConfigPath}.
    This does not work properly anymore and must be migrated to NixOS configuration.
    See https://doc.flyingcircus.io/roles/fc-22.05-production/postgresql.html for details.'';

  localConfig =
    if legacyConfigFiles != []
    then { include_dir = "${localConfigPath}"; }
    else {};

in {
  options = with lib; {

    flyingcircus.services.postgresql = {
      enable = mkEnableOption "Enable preconfigured PostgreSQL";

      autoUpgrade = {
        enable = mkEnableOption ''
          Automatically migrate old data dir when major version of PostgreSQL
          changes, using fc-postgresql/pg_upgrade.
          The old data dir will be kept and has to be removed manually later.
          You can run `sudo -u postgres fc-postgresql prepare-autoupgrade` to
          create the new data dir before upgrading PostgreSQL to reduce downtime
          and the risk of failure. You have to add databases to `expectedDatabases`
          or disable `checkExpectedDatabases` to make this work.
        '';
        checkExpectedDatabases = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Check that only the databases specified by `expectedDatabases`
            (and the standard internal databases) are present.
            This is enabled by default and prevents auto-upgrades affecting
            unexpected databases.
          '';
        };
        expectedDatabases = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''
            List of databases that are expected to be present before upgrading.
            If more databases are found, the upgrade will not run.
          '';
        };
      };

      majorVersion = mkOption {
          type = types.str;
          description = ''
            The major version of PostgreSQL to use (10, 11, 12, 13, 14).
          '';
        };
    };

  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable (
    let
      postgresqlPkg = getAttr cfg.majorVersion packages;

      extensions = lib.optionals (lib.versionOlder cfg.majorVersion "12") [
        (pkgs.postgis_2_5.override { postgresql = postgresqlPkg; })
        (pkgs.temporal_tables.override { postgresql = postgresqlPkg; })
        postgresqlPkg.pkgs.rum
      ] ++ lib.optionals (lib.versionAtLeast cfg.majorVersion "12") [
        postgresqlPkg.pkgs.periods
        postgresqlPkg.pkgs.postgis
        postgresqlPkg.pkgs.rum
      ];

    in {

      warnings =
        if legacyConfigFiles != []
        then [ legacyConfigWarning ]
        else [];

      systemd.services.postgresql.unitConfig = {
        ConditionPathExists = [
          # There is an upgrade running currently, postgresql must not start now.
          "!${upstreamCfg.dataDir}/fcio_stopper"
        ];
      };

      systemd.services.postgresql.bindsTo = [ "network-addresses-ethsrv.service" ];

      systemd.services.postgresql.preStart = lib.mkBefore ''
        if [[ -e ${upstreamCfg.dataDir}/fcio_migrated_to ]]; then
          echo "Error: cannot start because the migration marker ${upstreamCfg.dataDir}/fcio_migrated_to is present."
          echo "This data dir must not be used anymore if there is a newer data dir."
          echo "Maybe the wrong postgresql role version is selected?"
          echo "See 'sudo -u postgres fc-postgresql list-versions'"
          echo "and 'sudo -u postgres cat ${upstreamCfg.dataDir}/fcio_migrated_to.log'"
          echo "Only delete the marker if you sure that you want to use this data dir."
          exit 2
        fi

        if [[ -e ${upstreamCfg.dataDir}/fcio_upgrade_prepared ]]; then
          echo "Error: cannot start because the upgrade preparation marker ${upstreamCfg.dataDir}/fcio_upgrade_prepared is present."
          echo "Is there an unfinished manual upgrade or did you mean to enable autoupgrade?"
          echo "See 'sudo -u postgres fc-postgresql list-versions'"
          echo "and 'sudo -u postgres cat ${upstreamCfg.dataDir}/fcio_upgrade_prepared'"
          echo "Only delete the marker if you sure that you want to use this data dir."
          exit 2
        fi
      '';

      systemd.services.postgresql.postStart =
      let
        psql = "${postgresqlPkg}/bin/psql --port=${toString upstreamCfg.port}";
      in ''
        if ! ${psql} -c '\du' template1 | grep -q '^ *nagios *|'; then
          ${psql} -c 'CREATE ROLE nagios NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN' template1
        fi
        if ! ${psql} -l | grep -q '^ *nagios *|'; then
          ${postgresqlPkg}/bin/createdb --port ${toString upstreamCfg.port} nagios
        fi
        ${psql} -q -d nagios -c 'REVOKE ALL ON SCHEMA public FROM PUBLIC CASCADE;'

        ln -sfT ${postgresqlPkg} ${upstreamCfg.dataDir}/package
        ln -sfT ${upstreamCfg.dataDir}/package /nix/var/nix/gcroots/per-user/postgres/package_${cfg.majorVersion}
      '';

      systemd.services.postgresql.serviceConfig =
        lib.optionalAttrs (lib.versionAtLeast cfg.majorVersion "12") {
          RuntimeDirectory = "postgresql";
        };

      users.users.postgres = {
        shell = "/run/current-system/sw/bin/bash";
        home = lib.mkForce "/srv/postgresql";
      };

      environment.etc."local/postgresql/${cfg.majorVersion}/README.md".text = ''
        __WARNING__: Putting plain configuration here doesn’t work properly
        and must not be used anymore. Some options set here will be
        ignored silently if they are already defined by our platform
        code.
      '';

      environment.etc."local/postgresql/README.md".text = ''
        ${if legacyConfigFiles != [] then "**WARNING: " + legacyConfigWarning + "**\n" else ""}
        PostgreSQL ${cfg.majorVersion} is running on this system.

        You can override platform and PostgreSQL defaults by using the
        `services.postgresql.settings` option in a custom NixOS module. Place
        it in `/etc/local/nixos/postgresql.nix`, for example:

        ```nix
        { config, lib, ... }:
        {
          services.postgresql.settings = {
              log_connections = true;
              huge_pages = "try";
              max_connections = lib.mkForce 1000;
          }
        }
        ```

        See the platform documentation for more details:

        https://doc.flyingcircus.io/roles/fc-22.05-production/postgresql.html
      '';

      flyingcircus.infrastructure.preferNoneSchedulerOnSsd = true;

      flyingcircus.activationScripts = {
        postgresql-srv = lib.stringAfter [ "users" "groups" ] ''
          install -d -o postgres /srv/postgresql
          install -d -o postgres /nix/var/nix/gcroots/per-user/postgres
        '';
      };

      flyingcircus.localConfigDirs.postgresql = {
        dir = (toString localConfigPath);
        user = "postgres";
      };

      flyingcircus.passwordlessSudoRules = [
        # Service users may switch to the postgres system user
        {
          commands = [ "ALL" ];
          groups = [ "sudo-srv" "service" ];
          runAs = "postgres";
        }
        {
          commands = [
            "${pkgs.systemd}/bin/systemctl start postgresql"
            "${pkgs.systemd}/bin/systemctl stop postgresql"
          ];
          users = [ "postgres" ];
        }
      ];

      # System tweaks
      boot.kernel.sysctl = {
        "kernel.shmmax" = toString sharedMemoryMax;
        "kernel.shmall" = toString (sharedMemoryMax / 4096);
      };

      services.udev.extraRules = ''
        # increase readahead for postgresql
        SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{bdi/read_ahead_kb}="1024", ATTR{queue/read_ahead_kb}="1024"
      '';

      services.postgresql = {

        enable = true;
        # The config check is too strict for now because it doesn't build
        # when there's an error and fails even for our default config.
        # May happen when files are not accessible from the Nix sandbox.
        # Looks like that locale files cannot be found.
        # XXX: Switching it to a warning and filtering out locale issues
        # would be interesting.
        checkConfig = false;
        dataDir = "/srv/postgresql/${cfg.majorVersion}";
        extraPlugins = extensions;
        initialScript = ./postgresql-init.sql;
        logLinePrefix = "user=%u,db=%d ";
        package = postgresqlPkg;

        authentication = ''
          local postgres root       trust
          # trusted access for Nagios
          host    nagios          nagios          0.0.0.0/0               trust
          host    nagios          nagios          ::/0                    trust
          # authenticated access for others
          host all  all  0.0.0.0/0  md5
          host all  all  ::/0       md5
        '';

        settings = {
          #------------------------------------------------------------------------------
          # CONNECTIONS AND AUTHENTICATION
          #------------------------------------------------------------------------------
          listen_addresses = lib.mkOverride 50 (concatStringsSep "," listenAddresses);
          max_connections = 400;
          #------------------------------------------------------------------------------
          # RESOURCE USAGE (except WAL)
          #------------------------------------------------------------------------------
          # available memory: ${toString currentMemory}MB
          shared_buffers = "${toString sharedBuffers}MB"; # starting point is 25% RAM
          temp_buffers = "16MB";
          work_mem = "${toString workMem}MB";
          maintenance_work_mem = "${toString maintenanceWorkMem}MB";
          #------------------------------------------------------------------------------
          # QUERY TUNING
          #------------------------------------------------------------------------------
          effective_cache_size = "${toString (sharedBuffers * 2)}MB";

          random_page_cost = randomPageCost;
          # version-specific resource settings for >=9.3
          effective_io_concurrency = 100;

          #------------------------------------------------------------------------------
          # WRITE AHEAD LOG
          #------------------------------------------------------------------------------
          wal_level = "hot_standby";
          wal_buffers = "${toString walBuffers}MB";
          checkpoint_completion_target = 0.9;
          archive_mode = false;

          #------------------------------------------------------------------------------
          # ERROR REPORTING AND LOGGING
          #------------------------------------------------------------------------------
          log_min_duration_statement = 100;
          log_checkpoints = true;
          log_connections = true;
          log_lock_waits = true;
          log_autovacuum_min_duration = 5000;
          log_temp_files = "1kB";
          shared_preload_libraries = "auto_explain, pg_stat_statements";
          "auto_explain.log_min_duration" = "3s";

          #------------------------------------------------------------------------------
          # CLIENT CONNECTION DEFAULTS
          #------------------------------------------------------------------------------
          datestyle = "iso, mdy";
          lc_messages = "en_US.utf8";
          lc_monetary = "en_US.utf8";
          lc_numeric = "en_US.utf8";
          lc_time = "en_US.utf8";
        } // localConfig;

      };

      # PostgreSQL used /tmp as socket location in earlier NixOS versions.
      # That has been changed to /run/postgresql but users may still expect the old location.
      systemd.tmpfiles.rules = [
        "d /var/log/fc-agent/postgresql - postgres service"
        "L /tmp/.s.PGSQL.5432 - - - - /run/postgresql/.s.PGSQL.5432"
      ];

      flyingcircus.services = {

        sensu-client.checkEnvPackages = [
          postgresqlPkg
        ];

        sensu-client.checks =
          lib.optionalAttrs (cfg.autoUpgrade.enable && cfg.autoUpgrade.checkExpectedDatabases) {
            postgresql-autoupgrade-possible = {
              notification = "Unexpected PostgreSQL databases present, autoupgrade will fail!";
              command = "sudo -u postgres ${pkgs.fc.agent}/bin/fc-postgresql check-autoupgrade-unexpected-dbs";
              interval = 600;
            };
          } // (lib.listToAttrs (
          map (host:
              let saneHost = replaceStrings [":"] ["_"] host;
              in
              { name = "postgresql-listen-${saneHost}-5432";
                value = {
                  notification = "PostgreSQL listening on ${host}:5432";
                  command = ''
                    ${pkgs.sensu-plugins-postgres}/bin/check-postgres-alive.rb \
                      -h ${host} -u nagios -d nagios -P 5432 -T 10
                  '';
                  interval = 120;
                };
              })
            listenAddresses));

        telegraf.inputs = {
          postgresql = [
            (if (lib.versionOlder cfg.majorVersion "12") then {
              address = "host=/tmp user=root sslmode=disable dbname=postgres";
            }
            else {
              address = "host=/run/postgresql user=root sslmode=disable dbname=postgres";
              # Workaround for a telegraf bug: https://github.com/influxdata/telegraf/issues/6712
              ignored_databases = [ "postgres" "template0" "template1" ];
            })
          ];
        };
      };

    }))

    (lib.mkIf cfg.autoUpgrade.enable {
      environment.etc."local/postgresql/autoupgrade.json".text = toJSON {
        expected_databases = cfg.autoUpgrade.expectedDatabases;
      };

      systemd.services.fc-postgresql-autoupgrade = {
        path = with pkgs; [
          sudo
        ];

        before = [ "postgresql.service" ];
        requiredBy = [ "postgresql.service" ];

        script = let
          expectedDatabaseStr = lib.concatMapStringsSep " " (d: "--expected ${d}") cfg.autoUpgrade.expectedDatabases;
          upgradeCmd = [
            "${pkgs.fc.agent}/bin/fc-postgresql upgrade"
            "--new-version ${cfg.majorVersion}"
            "--new-data-dir ${upstreamCfg.dataDir}"
            "--new-bin-dir ${upstreamCfg.package}/bin"
            "--no-stop"
            "--nothing-to-do-is-ok"
            "--upgrade-now"
          ] ++ lib.optional cfg.autoUpgrade.checkExpectedDatabases
            "--existing-db-check ${expectedDatabaseStr}";
        in
          concatStringsSep " \\\n  " upgradeCmd;

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
          ProtectHome = true;
          ProtectSystem = true;
        };
        unitConfig = {
          ConditionPathExists = [
            # Don't try to autoupgrade if the new data dir has markers that
            # show that a migration already has happenend (fcio_migrated_from)
            # or that the postgresql.service already has used this directory (package).
            "!${upstreamCfg.dataDir}/fcio_migrated_from"
            "!${upstreamCfg.dataDir}/package"
          ];
        };
      };
    })
  ];
}
