{ config, lib, pkgs, ... }:

# TODO:
# consistency check / automatic maintenance?


with builtins;

let
  fclib = config.fclib;
in
{
  options = with lib;
  let
    mkRole = v: {
      enable = lib.mkEnableOption "Enable the Flying Circus MySQL / Percona ${v} server role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  in {

    flyingcircus.roles = {

      mysql = {

        # This is a placeholder role and should not be enabled
        # by itself and can't directly run on containers either.
        supportsContainers = fclib.mkDisableContainerSupport;

        listenAddresses = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = fclib.network.lo.dualstack.addresses ++
                    fclib.network.srv.dualstack.addresses;
        };

        extraConfig = mkOption {
          type = types.lines;
          default = "";
          description =
          ''
            Extra MySQL configuration to append at the end of the
            configuration file. Do not assume this to be located
            in any specific section.
          '';
        };
      };

      mysql57 = mkRole "5.7";
      percona80 = mkRole "8.0";
    };

  };

  config =
  let
    mysqlRoles = with config.flyingcircus.roles; {
      "5.7" = mysql57.enable;
      "8.0" = percona80.enable;
    };

    mysqlPackages = with pkgs; {
      "5.7" = percona57;
      "8.0" = percona80;
    };

    xtrabackupPackages = with pkgs; {
      "5.7" = percona-xtrabackup_2_4;
      "8.0" = percona-xtrabackup_8_0;
    };

    cfg = config.flyingcircus.roles.mysql;
    fclib = config.fclib;

    current_memory = fclib.currentMemory 256;
    cores = fclib.currentCores 1;

    localConfigPath = /etc/local/mysql;

    rootPasswordFile = "${toString localConfigPath}/mysql.passwd";

    isCnf = path: t: lib.hasSuffix ".cnf" path;

    localConfig =
      if pathExists localConfigPath
      then "!includedir ${filterSource isCnf localConfigPath}"
      else "";

    enabledRoles = lib.filterAttrs (n: v: v) mysqlRoles;
    enabledRolesCount = length (lib.attrNames enabledRoles);
    version = head (lib.attrNames enabledRoles);
    package = mysqlPackages.${version} or null;
    xtraPackage = xtrabackupPackages.${version};

    telegrafPassword = fclib.derivePasswordForHost "mysql-telegraf";
    sensuPassword = fclib.derivePasswordForHost "mysql-sensu";

    mysqlCheck = ''
      ${pkgs.sensu-plugins-mysql}/bin/check-mysql-alive.rb \
        -s /run/mysqld/mysqld.sock -d fc_sensu \
        --user fc_sensu --pass ${sensuPassword}
    '';

  in lib.mkMerge [

  (lib.mkIf (enabledRolesCount > 0) {
    assertions =
      [
        {
          assertion = enabledRolesCount == 1;
          message = "MySQL / Percona roles are mutually exclusive. Only one may be enabled.";
        }
      ];

    users.users.mysql = {
      shell = "/run/current-system/sw/bin/bash";
      home = lib.mkForce "/srv/mysql";
      # ensure we can properly set things up first time
      createHome = true;
    };

    flyingcircus.passwordlessSudoRules = [
      # Service users may switch to the mysql system user
      {
        commands = [ "ALL" ];
        groups = [ "sudo-srv" "service" ];
        runAs = "mysql";
      }
    ];

    systemd.tmpfiles.rules = [
      "d /var/log/mysql 0755 mysql service 90d"
      "f /var/log/mysql/mysql.slow 0640 mysql service -"
    ];

    # Note that this does not use platform defaults, by using priority 100.
    # postrotate command taken from https://www.percona.com/blog/2013/04/18/rotating-mysql-slow-logs-safely/
    services.logrotate.settings = {
      "/var/log/mysql/mysql.slow" = {
        priority = 100;
        rotate = 10;
        frequency = "weekly";
        maxsize = "2G";
        compress = true;
        create = "0640 mysql service";
        postrotate = ''
          ${package}/bin/mysql --defaults-extra-file=/root/.my.cnf -e \
                'select @@global.long_query_time into @lqt_save; set global long_query_time=2000; select sleep(2); FLUSH LOGS; select sleep(2); set global long_query_time=@lqt_save;'
        '';
        missingok = true;
      };
    };

    services.percona = {
      enable = true;
      inherit package rootPasswordFile;
      dataDir = "/srv/mysql";
      extraOptions =
        let
          charset = if (lib.versionAtLeast package.version "8.0")
                    then "utf8mb4"
                    else "utf8";
          collation = if (lib.versionAtLeast package.version "8.0")
                      then "utf8mb4_unicode_ci"
                      else "utf8_unicode_ci";
        in ''
        [mysqld]
        default-storage-engine  = innodb
        skip-external-locking
        skip-name-resolve
        max_allowed_packet         = 512M
        bulk_insert_buffer_size    = 128M
        tmp_table_size             = 512M
        max_heap_table_size        = 512M
        lower-case-table-names     = 0
        max_connect_errors         = 20
        default_storage_engine     = InnoDB
        table_definition_cache     = 512
        open_files_limit           = 65535
        sysdate-is-now             = ON
        sql_mode                   = NO_ENGINE_SUBSTITUTION

        log_slow_verbosity = 'full'
        slow_query_log = ON
        long_query_time = 0.1
        log_slow_slave_statements = ON
        slow_query_log_file = '/var/log/mysql/mysql.slow'
        log_slow_admin_statements = ON
        log_queries_not_using_indexes = ON
        log_throttle_queries_not_using_indexes = 50

        init-connect               = 'SET NAMES ${charset} COLLATE ${collation}'
        character-set-server       = ${charset}
        collation-server           = ${collation}
        character_set_server       = ${charset}
        collation_server           = ${collation}

        interactive_timeout        = 28800
        wait_timeout               = 28800
        connect_timeout            = 10

        ${ # versions before 8.0.13 don't support binding to multiple IPs
           # so we must bind to 0.0.0.0
          if (lib.versionAtLeast package.version "8.0")
          then
          "bind-address               = ${lib.concatStringsSep "," cfg.listenAddresses}"
          else
          "bind-address               = 0.0.0.0"
        }
        max_connections            = 1000
        thread_cache_size          = 128
        myisam-recover-options     = FORCE
        key_buffer_size            = 64M
        table_open_cache           = 1000
        # myisam-recover           = FORCE
        thread_cache_size          = 8

        ${# For 8.0 we still use native password because there are
          # too many non 8.0 client libs out there, which cannot
          # connect otherwise.
          lib.optionalString
          (lib.versionAtLeast package.version "8.0")
          "default_authentication_plugin = mysql_native_password"}

        ${# Query cache is gone in 8.0
          # https://mysqlserverteam.com/mysql-8-0-retiring-support-for-the-query-cache/
          lib.optionalString
          (lib.versionOlder package.version "8.0")
          ''query_cache_type           = 1
            query_cache_min_res_unit   = 2k
            query_cache_size           = 80M
          ''}

        # * InnoDB
        innodb_buffer_pool_size         = ${toString (current_memory * 70 / 100)}M
        innodb_log_buffer_size          = 64M
        innodb_file_per_table           = 1
        innodb_read_io_threads          = ${toString (cores * 4)}
        innodb_write_io_threads         = ${toString (cores * 4)}
        # Percentage. Probably needs local tuning depending on the workload.
        innodb_change_buffer_max_size   = 50
        innodb_doublewrite              = 1
        innodb_log_file_size            = 512M
        innodb_log_files_in_group       = 4
        innodb_flush_method             = O_DSYNC
        innodb_open_files               = 800
        innodb_stats_on_metadata        = 0
        innodb_lock_wait_timeout        = 120

        [mysqldump]
        quick
        quote-names
        max_allowed_packet    = 512M

        [xtrabackup]
        target_dir                      = /opt/backup/xtrabackup
        compress-threads                = ${toString (cores * 2)}
        compress
        parallel            = 3

        [isamchk]
        key_buffer        = 16M

        # flyingcircus.roles.mysql.extraConfig
        ${cfg.extraConfig}

        # /etc/local/mysql/*
        ${localConfig}
      '';
    };

    flyingcircus.localConfigDirs.mysql = {
      dir = (toString localConfigPath);
      user = "mysql";
    };

    environment.etc."local/mysql/README.txt".text = ''
      MySQL / Percona (${package.name}) is running on this machine.

      You can find the password for the MySQL root user in the file `mysql.passwd`.
      Service users can read the password file.

      Config files from this directory (/etc/local/mysql) are included in the
      mysql configuration. To set custom options, add a `local.cnf`
      (or any other *.cnf) file here, and run `sudo fc-manage --build`.

      ATTENTION: Changes to *.cnf files in this directory will restart MySQL
      to activate the new configuration.

      You can change the password for the mysql root user in the file `mysql.passwd`.
      The MySQL service must be restarted to pick up the new password:
      `sudo systemctl restart mysql`

      For more information, see our documentation at
      https://doc.flyingcircus.io/roles/fc-22.05-production/mysql.html
    '';

    systemd.services.fc-mysql-post-init = {
      description = "Prepare mysql for monitoring.";
      partOf = [ "mysql.service" ];
      requiredBy = [ "mysql.service" ];
      after = [ "mysql.service" ];
      path = [ package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script =
      let
        ensureUserAndDatabase = username: password:
          if (lib.versionAtLeast version "8.0") then ''
            CREATE USER IF NOT EXISTS ${username}@localhost IDENTIFIED BY '${password}';
            ALTER USER ${username}@localhost IDENTIFIED BY '${password}';
            CREATE DATABASE IF NOT EXISTS ${username};
            GRANT SELECT ON ${username}.* TO ${username}@localhost;
          ''
          else ''
            CREATE DATABASE IF NOT EXISTS ${username};
            GRANT SELECT ON ${username}.* TO ${username}@localhost IDENTIFIED BY '${password}';
          '';
        mysqlCmd = sql: ''mysql --defaults-extra-file=/root/.my.cnf -e "${sql}"'';
      in ''
          # Wait until the MySQL server is available for use
          count=0
          running=0
          while [ $running -eq 0 ]
          do
              if [ $count -eq 60 ]
              then
                  echo "Tried 60 times, giving up..."
                  exit 1
              fi

              echo "No MySQL server contact after $count attempts. Waiting..."
              count=$((count+1))
              ${mysqlCmd "SELECT 'MySQL is working!'"} && running=1
              sleep 3
          done

          # Create user and database for sensu, if they do not exist and make sure that the password is set
          ${mysqlCmd (ensureUserAndDatabase "fc_sensu" sensuPassword)}

          # Create user and database for telegraf, if they do not exist and make sure that the password is set
          ${mysqlCmd (ensureUserAndDatabase "fc_telegraf" telegrafPassword)}
        '';
    };

    services.udev.extraRules = ''
      # increase readahead for mysql
      SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{bdi/read_ahead_kb}="1024", ATTR{queue/read_ahead_kb}="1024"
    '';

    security.sudo.extraRules = [
      { groups = ["service"]; commands = [ { command = "${xtraPackage}/bin/xtrabackup"; options = [ "NOPASSWD" ]; } ]; }
    ];

    environment.systemPackages = with pkgs; [
      innotop
      xtraPackage
    ];

    flyingcircus.services = {
      sensu-client.checks = {
        mysql = {
          notification = "MySQL alive";
          command = mysqlCheck;
        };
      };

      telegraf.inputs = {
        mysql = [{
          servers = ["fc_telegraf:${telegrafPassword}@unix(/run/mysqld/mysqld.sock)/?tls=false"];
        }];
      };
    };
  })

  {
    flyingcircus.roles.statshost.prometheusMetricRelabel = [
      {
        source_labels = [ "__name__" "command" ];
        # Only if there is no command set.
        regex = "(mysql_commands)_(.+);$";
        replacement = "\${2}";
        target_label = "command";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_commands)_(.+)";
        replacement = "\${1}_total";
        target_label = "__name__";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_handler)_(.+)";
        replacement = "\${2}";
        target_label = "handler";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_handler)_(.+)";
        replacement = "mysql_handlers_total";
        target_label = "__name__";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_innodb_rows)_(.+)";
        replacement = "\${2}";
        target_label = "operation";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_innodb_rows)_(.+)";
        replacement = "mysql_innodb_row_ops_total";
        target_label = "__name__";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_innodb_buffer_pool_pages)_(.+)";
        replacement = "\${2}";
        target_label = "state";
      }
      {
        source_labels = [ "__name__" ];
        regex = "(mysql_innodb_buffer_pool_pages)_(.+)";
        replacement = "mysql_buffer_pool_pages";
        target_label = "__name__";
      }
    ];
  }
  ];
}
