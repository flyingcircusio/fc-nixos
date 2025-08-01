{
  config,
  lib,
  pkgs,
  ...
}:

# TODO:
# consistency check / automatic maintenance?

with builtins;

let
  fclib = config.fclib;
  supportedPerconaVersions = [
    "8.0"
    "8.3"
    "8.4"
  ];
  removeDot = builtins.replaceStrings [ "." ] [ "" ];
  lokiServer = fclib.findOneService "loki-collector";
in
{
  options =
    with lib;
    let
      mkRole = v: {
        enable = lib.mkEnableOption "Enable the Flying Circus MySQL / Percona ${v} server role.";
        supportsContainers = fclib.mkEnableDevhostSupport;
      };
    in
    {

      flyingcircus.roles = {

        mysql = {

          # This is a placeholder role and should not be enabled
          # by itself and can't directly run on containers either.
          supportsContainers = fclib.mkDisableDevhostSupport;

          binlogExpireDays = mkOption {
            type = types.ints.positive;
            default = 3;
            description = ''
              Expire binlog after 3 days by default.
              The MySQL/Percona default of 30 days is way too long for typical use cases.
            '';
          };

          listenAddresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = fclib.network.lo.dualstack.addresses ++ fclib.network.srv.dualstack.addresses;
            defaultText = "the addresses of the networks `lo` and `srv` (IPv4 & IPv6)";
          };

          bufferMemoryPercentage = lib.mkOption {
            type = lib.types.ints.between 0 100;
            default = 70;
            description = ''
              Percentage of the host's memory used by InnoDB for buffering.
              This is the primary memory use source of MySQL/Percona.
            '';
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = ''
              Extra MySQL configuration to append at the end of the
              configuration file. Do not assume this to be located
              in any specific section.
            '';
          };
        };

        mysql57 = mkRole "5.7";
      }
      // lib.listToAttrs (
        builtins.map (
          ver: lib.nameValuePair "percona${removeDot ver}" (mkRole ver)
        ) supportedPerconaVersions
      );

    };

  config =
    let
      mysqlRoles = {
        "5.7" = config.flyingcircus.roles.mysql57.enable;
      }
      // lib.listToAttrs (
        builtins.map (
          ver: lib.nameValuePair ver config.flyingcircus.roles."percona${removeDot ver}".enable
        ) supportedPerconaVersions
      );

      mysqlPackages = {
        "5.7" = pkgs.percona57;
      }
      // lib.listToAttrs (
        builtins.map (ver: lib.nameValuePair ver pkgs."percona${removeDot ver}") supportedPerconaVersions
      );

      xtrabackupPackages =
        with pkgs;
        {
          "5.7" = percona-xtrabackup_2_4;
        }
        // lib.listToAttrs (
          builtins.map (
            ver: lib.nameValuePair ver pkgs."percona-xtrabackup_${builtins.replaceStrings [ "." ] [ "_" ] ver}"
          ) supportedPerconaVersions
        );

      cfg = config.flyingcircus.roles.mysql;
      fclib = config.fclib;

      current_memory = fclib.currentMemory 256;
      cores = fclib.currentCores 1;

      localConfigPath = /etc/local/mysql;

      isCnf = path: t: lib.hasSuffix ".cnf" path;

      localConfig =
        if pathExists localConfigPath then "!includedir ${filterSource isCnf localConfigPath}" else "";

      enabledRoles = lib.filterAttrs (n: v: v) mysqlRoles;
      enabledRolesCount = length (lib.attrNames enabledRoles);
      version = head (lib.attrNames enabledRoles);
      package = mysqlPackages.${version} or null;
      xtraPackage = xtrabackupPackages.${version};
      mysqlCheck =
        "${package}/bin/mysql -u fc_sensu fc_sensu"
        + " --connect-timeout=10 --silent --batch -e"
        + ''"select version()" || exit 2'';

    in
    lib.mkMerge [

      (lib.mkIf (enabledRolesCount > 0) {
        assertions = [
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
            groups = [
              "sudo-srv"
              "service"
            ];
            runAs = "mysql";
          }
        ];

        flyingcircus.passwordlessSudoPackages = [
          {
            commands = [ "bin/xtrabackup" ];
            package = xtraPackage;
            groups = [ "service" ];
          }
        ];

        systemd.tmpfiles.rules = [
          "d /var/log/mysql 0755 mysql service 90d"
          "f /var/log/mysql/mysql.slow 0640 mysql service -"
          # Cleanup files that are not required anymore and confusing
          "r /root/.my.cnf"
          "r ${toString localConfigPath}/mysql.passwd"
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
              ${package}/bin/mysql -e \
                    'select @@global.long_query_time into @lqt_save; set global long_query_time=2000; select sleep(2); FLUSH LOGS; select sleep(2); set global long_query_time=@lqt_save;'
            '';
            missingok = true;
          };
        };

        services.percona = {
          enable = true;
          inherit package;
          dataDir = "/srv/mysql";
          extraOptions =
            let
              charset = if (lib.versionAtLeast package.version "8.0") then "utf8mb4" else "utf8";
              collation =
                if (lib.versionAtLeast package.version "8.0") then "utf8mb4_unicode_ci" else "utf8_unicode_ci";
            in
            ''
              [mysqld]
              default-storage-engine  = innodb
              plugin-load-add         = auth_socket.so
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

              ${
                if (lib.versionAtLeast package.version "8.0") then
                  "binlog_expire_logs_seconds = ${toString (cfg.binlogExpireDays * 24 * 60 * 60)}"
                else
                  "expire_logs_days = ${toString cfg.binlogExpireDays}"
              }
              log_slow_verbosity = 'full'
              slow_query_log = ON
              long_query_time = 0.1
              log_slow_slave_statements = ON
              slow_query_log_file = '/var/log/mysql/mysql.slow'
              log_slow_admin_statements = ON
              log_queries_not_using_indexes = ON
              log_throttle_queries_not_using_indexes = 5

              init-connect               = 'SET NAMES ${charset} COLLATE ${collation}'
              character-set-server       = ${charset}
              collation-server           = ${collation}
              character_set_server       = ${charset}
              collation_server           = ${collation}

              interactive_timeout        = 28800
              wait_timeout               = 28800
              connect_timeout            = 10

              ${
                # versions before 8.0.13 don't support binding to multiple IPs
                # so we must bind to 0.0.0.0
                if (lib.versionAtLeast package.version "8.0") then
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

              ${
                # For 8.4 we need to enable this manually. Will be removed in 9.0
                lib.optionalString (lib.versionAtLeast package.version "8.4") ''
                  mysql_native_password = ON
                ''
              }

              ${
                # For 8.0 and 8.3 we still use native password because there are
                # too many non 8.0 client libs out there, which cannot
                # connect otherwise.
                lib.optionalString
                  (lib.versionAtLeast package.version "8.0" && lib.versionOlder package.version "8.4")
                  ''
                    default_authentication_plugin = mysql_native_password
                    log_error_suppression_list = MY-013360
                  ''
              }

              ${
                # Query cache is gone in 8.0
                # https://mysqlserverteam.com/mysql-8-0-retiring-support-for-the-query-cache/
                lib.optionalString (lib.versionOlder package.version "8.0") ''
                  query_cache_type           = 1
                  query_cache_min_res_unit   = 2k
                  query_cache_size           = 80M
                ''
              }

              # * InnoDB
              innodb_buffer_pool_size         = ${toString (current_memory * cfg.bufferMemoryPercentage / 100)}M
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

          The root user is authenticated by socket auth with the `mysql` and `root` system users.
          If you want to add a password to this user, you can do this manually with interactive
          SQL commands.

          Config files from this directory (/etc/local/mysql) are included in the
          mysql configuration. To set custom options, add a `local.cnf`
          (or any other *.cnf) file here, and run `sudo fc-manage switch`.

          ATTENTION: Changes to *.cnf files in this directory will restart MySQL
          to activate the new configuration.

          For more information, see our documentation at
          ${fclib.roleDocUrl "mysql"}
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
              ensureUserAndDatabase =
                dbUser: systemUser:
                if (lib.versionAtLeast version "8.0") then
                  ''
                    CREATE USER IF NOT EXISTS ${dbUser}@localhost IDENTIFIED WITH auth_socket AS '${systemUser}';
                    ALTER USER ${dbUser}@localhost IDENTIFIED WITH auth_socket AS '${systemUser}';
                    CREATE DATABASE IF NOT EXISTS ${dbUser};
                    GRANT SELECT ON ${dbUser}.* TO ${dbUser}@localhost;
                  ''
                else
                  ''
                    CREATE DATABASE IF NOT EXISTS ${dbUser};
                    GRANT SELECT ON ${dbUser}.* TO ${dbUser}@localhost IDENTIFIED WITH auth_socket AS '${systemUser}';
                  '';
              mysqlCmd = sql: ''mysql -e "${sql}"'';
            in
            ''
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

              # Create user and database for monitoring, if they do not exist and set up socket auth.
              ${mysqlCmd (ensureUserAndDatabase "fc_sensu" "sensuclient")}
              ${mysqlCmd (ensureUserAndDatabase "fc_telegraf" "telegraf")}
            '';
        };

        services.udev.extraRules = ''
          # increase readahead for mysql
          SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{bdi/read_ahead_kb}="1024", ATTR{queue/read_ahead_kb}="1024"
        '';

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
            mysql = [
              {
                servers = [ "fc_telegraf@unix(/run/mysqld/mysqld.sock)/?tls=false" ];
              }
            ];
          };
        };
      })

      {
        flyingcircus.roles.statshost.prometheusMetricRelabel = [
          {
            source_labels = [
              "__name__"
              "command"
            ];
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

      (lib.mkIf (!builtins.isNull lokiServer) {
        systemd.services.alloy = lib.mkIf config.services.alloy.enable {
          reloadTriggers = [ config.environment.etc."alloy/mysql_slowlog.alloy".source ];
          serviceConfig.SupplementaryGroups = [ "service" ];
        };

        environment.etc."alloy/mysql_slowlog.alloy".text = ''
          local.file_match "mysql_slowlogs" {
              path_targets = [{
                  __path__ = "/var/log/mysql/mysql.slow",
                  job_name = "mysql/slowlogs",
              }]
          }

          loki.source.file "mysql_slowlogs" {
              targets    = local.file_match.mysql_slowlogs.targets
              forward_to = [loki.process.mysql_slowlogs.receiver]
          }

          loki.process "mysql_slowlogs" {
              forward_to = [loki.write.fcio_rg_loki.receiver]

              stage.multiline {
                  firstline = "^# Time: (?P<time>.+?)"
              }

              stage.regex {
                  // the patterns are separated by a non-greedy match-everything
                  // the query pattern matches everything after the first line that doesnt start with a '#'
                  // since this is a regular regex, the order of these capture groups is very important
                  // when in doubt, check the slow log file itself for the correct order
                  expression = "${
                    lib.escape [ "\"" "\\" ] (
                      "(?s)^.*?"
                      + (builtins.concatStringsSep ".*?" [
                        "Time: (?P<time>.+Z)"
                        "User@Host: (?P<user>\\S+) @ (?P<host>\\S+)"
                        "Id:\\s+(?P<id>\\d+)"
                        "Schema: (?P<schema>\\S*?)?"
                        "Last_errno: (?P<last_errno>\\d+)"
                        "Killed: (?P<killed>\\d+)"
                        "Query_time: (?P<query_time>\\S+)"
                        "Lock_time: (?P<lock_time>\\S+)"
                        "Rows_sent: (?P<rows_sent>\\d+)"
                        "Rows_examined: (?P<rows_examined>\\d+)"
                        "Rows_affected: (?P<rows_affected>\\d+)"
                        "Bytes_sent: (?P<bytes_sent>\\d+)"
                        "Tmp_tables: (?P<tmp_tables>\\d+)"
                        "Tmp_disk_tables: (?P<tmp_disk_tables>\\d+)"
                        "Tmp_table_sizes: (?P<tmp_table_sizes>\\d+)"
                        # "QC_Hit: (?P<qc_hit>\\S+)"
                        "Full_scan: (?P<full_scan>\\S+)"
                        "Full_join: (?P<full_join>\\S+)"
                        "Tmp_table: (?P<tmp_table>\\S+)"
                        "Tmp_table_on_disk: (?P<tmp_table_on_disk>\\S+)"
                        "Filesort: (?P<filesort>\\S+)"
                        "Filesort_on_disk: (?P<filesort_on_disk>\\S+)"
                        "Merge_passes: (?P<merge_passes>\\d+)"
                        "SET timestamp=(.*?);"
                      ])
                      + ".*?\\n(?P<query>[^#](?s:.+))"
                    )
                  }"
              }

              stage.labels {
                  values = {
                      time = null,
                      user = null,
                  }
              }

              stage.timestamp {
                  source = "time"
                  format = "RFC3339Nano"
              }

              stage.template {
                  source   = "output_line"
                  template = "${
                    lib.escape [ "\"" "\\" ] (
                      builtins.concatStringsSep " " (
                        map (field: "${field}=\"{{ Replace .${field} \"\\n\" \" \" -1 }}\"") [
                          "id"
                          "schema"
                          "last_errno"
                          "killed"
                          "query_time"
                          "lock_time"
                          "rows_sent"
                          "rows_affected"
                          "bytes_sent"
                          "tmp_tables"
                          "tmp_disk_tables"
                          "tmp_table_sizes"
                          "full_scan"
                          "full_join"
                          "tmp_table"
                          "tmp_table_on_disk"
                          "filesort"
                          "filesort_on_disk"
                          "merge_passes"
                          "query"
                        ]
                      )
                    )
                  }"
              }

              stage.output {
                  source = "output_line"
              }
          }
        '';
      })
    ];
}
