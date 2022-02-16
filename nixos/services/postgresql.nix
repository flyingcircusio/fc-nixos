{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.postgresql;
  fclib = config.fclib;
  packages = {
    "9.6" = pkgs.postgresql_9_6;
    "10" = pkgs.postgresql_10;
    "11" = pkgs.postgresql_11;
    "12" = pkgs.postgresql_12;
    "13" = pkgs.postgresql_13;
  };

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

  localConfig =
    if pathExists localConfigPath
    then { include_dir = "${localConfigPath}"; }
    else {};

in {
  options = with lib; {

    flyingcircus.services.postgresql = {
      enable = mkEnableOption "Enable preconfigured PostgreSQL";
      majorVersion = mkOption {
          type = types.str;
          description = ''
            The major version of PostgreSQL to use (9.6, 10, 11, 12, 13).
          '';
        };
    };

  };

  config =
  (lib.mkIf cfg.enable (
  let
    postgresqlPkg = getAttr cfg.majorVersion packages;

    extensions = lib.optionals (lib.versionOlder cfg.majorVersion "12") [
      (pkgs.postgis_2_5.override { postgresql = postgresqlPkg; })
      (pkgs.temporal_tables.override { postgresql = postgresqlPkg; })
      (pkgs.rum.override { postgresql = postgresqlPkg; })
    ] ++ lib.optionals (lib.versionAtLeast cfg.majorVersion "12") [
      postgresqlPkg.pkgs.periods
      postgresqlPkg.pkgs.postgis
      (pkgs.rum.override { postgresql = postgresqlPkg; })
    ];

  in {

    systemd.services.postgresql.bindsTo = [ "network-addresses-ethsrv.service" ];

    systemd.services.postgresql.postStart =
    let
      psql = "${postgresqlPkg}/bin/psql --port=${toString config.services.postgresql.port}";
    in ''
      if ! ${psql} -c '\du' template1 | grep -q '^ *nagios *|'; then
        ${psql} -c 'CREATE ROLE nagios NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN' template1
      fi
      if ! ${psql} -l | grep -q '^ *nagios *|'; then
        ${postgresqlPkg}/bin/createdb --port ${toString config.services.postgresql.port} nagios
      fi
      ${psql} -q -d nagios -c 'REVOKE ALL ON SCHEMA public FROM PUBLIC CASCADE;'
    '';

    systemd.services.postgresql.serviceConfig =
      lib.optionalAttrs (lib.versionAtLeast cfg.majorVersion "12") {
        RuntimeDirectory = "postgresql";
      };

    users.users.postgres = {
      shell = "/run/current-system/sw/bin/bash";
      home = lib.mkForce "/srv/postgresql";
    };

    environment.etc."local/postgresql/${cfg.majorVersion}/README.txt".text = ''
        Put your local postgresql configuration here. This directory
        is being included with include_dir.
        '';

    flyingcircus.infrastructure.preferNoneSchedulerOnSsd = true;

    flyingcircus.activationScripts = {
      postgresql-srv = lib.stringAfter [ "users" "groups" ] ''
        install -d -o postgres /srv/postgresql
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
      "L /tmp/.s.PGSQL.5432 - - - - /run/postgresql/.s.PGSQL.5432"
    ];

    flyingcircus.services = {

      sensu-client.checks =
        lib.listToAttrs (
        map (host:
            let saneHost = replaceStrings [":"] ["_"] host;
            in
            { name = "postgresql-listen-${saneHost}-5432";
              value = {
                notification = "PostgreSQL listening on ${host}:5432";
                command = ''
                  ${pkgs.sensu-plugins-postgres}/bin/check-postgres-alive.rb \
                    -h ${host} -u nagios -d nagios -P 5432
                '';
                interval = 120;
              };
            })
          listenAddresses);

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

  }));
}
