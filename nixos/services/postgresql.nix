{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.postgresql;
  fclib = config.fclib;
  packages = {
    "9.5" = pkgs.postgresql95;
    "9.6" = pkgs.postgresql96;
    "10" = pkgs.postgresql_10;
    "11" = pkgs.postgresql_11;
  };

  listenAddresses =
    fclib.listenAddresses "lo" ++
    fclib.listenAddresses "ethsrv";

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
    then "include_dir '${localConfigPath}'"
    else "";

in {
  options = with lib; {

    flyingcircus.services.postgresql = {
      enable = mkEnableOption "Enable preconfigured PostgreSQL";
      majorVersion = mkOption {
          type = types.string;
          description = ''
            The major version of PostgreSQL to use (9.5, 9.6, 10, 11).
          '';
        };
    };

  };

  config = 
  (lib.mkIf cfg.enable (
  let
    postgresqlPkg = getAttr cfg.majorVersion packages;

  in {

    services.postgresql.enable = true;
    services.postgresql.package = postgresqlPkg;
    services.postgresql.extraPlugins = [
      (pkgs.temporal_tables.override { postgresql = postgresqlPkg; })
      (pkgs.postgis.override { postgresql = postgresqlPkg; })
    ] ++ lib.optionals
      (lib.versionAtLeast cfg.majorVersion "9.6")
      [ (pkgs.rum.override { postgresql = postgresqlPkg; }) ];

    services.postgresql.initialScript = ./postgresql-init.sql;
    services.postgresql.dataDir = "/srv/postgresql/${cfg.majorVersion}";
    systemd.services.postgresql.bindsTo = [ "network-addresses-ethsrv.service" ];

    systemd.services.postgresql.postStart =
    let
      psql = "${postgresqlPkg}/bin/psql";
    in ''
      if ! ${psql} -c '\du' template1 | grep -q '^ *nagios *|'; then
        ${psql} -c 'CREATE ROLE nagios NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT LOGIN' template1
      fi
      if ! ${psql} -l | grep -q '^ *nagios *|'; then
        ${postgresqlPkg}/bin/createdb nagios
      fi
      ${psql} -q -d nagios -c 'REVOKE ALL ON SCHEMA public FROM PUBLIC CASCADE;'
    '';

    users.users.postgres = {
      shell = "/run/current-system/sw/bin/bash";
      home = lib.mkForce "/srv/postgresql";
    };

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
      SUBSYSTEM=="block", ATTR{queue/rotational}=="1", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{bdi/read_ahead_kb}="1024", ATTR{queue/read_ahead_kb}="1024"
    '';

    # Custom postgresql configuration
    services.postgresql.extraConfig = ''
      #------------------------------------------------------------------------------
      # CONNECTIONS AND AUTHENTICATION
      #------------------------------------------------------------------------------
      listen_addresses = '${concatStringsSep "," listenAddresses}'
      max_connections = 400
      #------------------------------------------------------------------------------
      # RESOURCE USAGE (except WAL)
      #------------------------------------------------------------------------------
      # available memory: ${toString currentMemory}MB
      shared_buffers = ${toString sharedBuffers}MB   # starting point is 25% RAM
      temp_buffers = 16MB
      work_mem = ${toString workMem}MB
      maintenance_work_mem = ${toString maintenanceWorkMem}MB
      #------------------------------------------------------------------------------
      # QUERY TUNING
      #------------------------------------------------------------------------------
      effective_cache_size = ${toString (sharedBuffers * 2)}MB

      random_page_cost = ${toString randomPageCost}
      # version-specific resource settings for >=9.3
      effective_io_concurrency = 100

      #------------------------------------------------------------------------------
      # WRITE AHEAD LOG
      #------------------------------------------------------------------------------
      wal_level = hot_standby
      wal_buffers = ${toString walBuffers}MB
      checkpoint_completion_target = 0.9
      archive_mode = off

      #------------------------------------------------------------------------------
      # ERROR REPORTING AND LOGGING
      #------------------------------------------------------------------------------
      log_min_duration_statement = 1000
      log_checkpoints = on
      log_connections = on
      log_line_prefix = 'user=%u,db=%d '
      log_lock_waits = on
      log_autovacuum_min_duration = 5000
      log_temp_files = 1kB
      shared_preload_libraries = 'auto_explain'
      auto_explain.log_min_duration = '3s'

      #------------------------------------------------------------------------------
      # CLIENT CONNECTION DEFAULTS
      #------------------------------------------------------------------------------
      datestyle = 'iso, mdy'
      lc_messages = 'en_US.utf8'
      lc_monetary = 'en_US.utf8'
      lc_numeric = 'en_US.utf8'
      lc_time = 'en_US.utf8'

      ${localConfig}
    '';

    environment.etc."local/postgresql/${cfg.majorVersion}/README.txt".text = ''
        Put your local postgresql configuration here. This directory
        is being included with include_dir.
        '';

    services.postgresql.authentication = ''
      local postgres root       trust
      # trusted access for Nagios
      host    nagios          nagios          0.0.0.0/0               trust
      host    nagios          nagios          ::/0                    trust
      # authenticated access for others
      host all  all  0.0.0.0/0  md5
      host all  all  ::/0       md5
    '';

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
        postgresql = [{
          address = "host=/tmp user=root sslmode=disable dbname=postgres";
        }];
      };
    };

  }));
}
