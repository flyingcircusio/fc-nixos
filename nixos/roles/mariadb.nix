{
  config,
  lib,
  pkgs,
  ...
}:

# TODO:
# consistency check / automatic maintenance?

let
  fclib = config.fclib;
  supportedMariaDBVersions = [
    "114"
    "118"
  ];
  lokiServer = fclib.findOneService "loki-collector";
  isCnf = path: t: lib.hasSuffix ".cnf" path;
  inherit (builtins)
    pathExists
    filterSource
    length
    head
    ;
in
{
  options =
    let
      mkRole = v: {
        enable = lib.mkEnableOption "Enable the Flying Circus MariaDB ${v} server role.";
        supportsContainers = fclib.mkEnableDevhostSupport;
      };
    in
    {
      flyingcircus.roles = {
        mariadb = {
          # This is a placeholder role and should not be enabled
          # by itself and can't directly run on containers either.
          supportsContainers = fclib.mkDisableDevhostSupport;

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
              This is the primary memory use source of MariaDB.
            '';
          };
        };
      }
      // lib.listToAttrs (
        builtins.map (ver: lib.nameValuePair "mariadb${ver}" (mkRole ver)) supportedMariaDBVersions
      );
    };

  config =
    let
      mariadbRoles = lib.listToAttrs (
        builtins.map (
          ver: lib.nameValuePair ver config.flyingcircus.roles."mariadb${ver}".enable
        ) supportedMariaDBVersions
      );

      mariadbPackages = lib.listToAttrs (
        builtins.map (ver: lib.nameValuePair ver pkgs."mariadb_${ver}") supportedMariaDBVersions
      );

      cfg = config.flyingcircus.roles.mariadb;
      fclib = config.fclib;

      current_memory = fclib.currentMemory 256;
      cores = fclib.currentCores 1;

      localConfigPath = /etc/local/mariadb;

      enabledRoles = lib.filterAttrs (n: v: v) mariadbRoles;
      enabledRolesCount = length (lib.attrNames enabledRoles);
      version = head (lib.attrNames enabledRoles);
      package = mariadbPackages.${version} or null;

      mariadbCheck =
        "${package}/bin/mariadb -u sensuclient sensuclient"
        + " --connect-timeout=10 --silent --batch -e"
        + ''"select version()" || exit 2'';

    in
    lib.mkIf (enabledRolesCount > 0) (
      lib.mkMerge [
        {
          assertions = [
            {
              assertion = enabledRolesCount == 1;
              message = "MariaDB roles are mutually exclusive. Only one may be enabled.";
            }
          ];

          users.extraUsers.mariadb = {
            group = "mariadb";
            shell = "/run/current-system/sw/bin/bash";
            home = lib.mkForce "/srv/mariadb";
            # ensure we can properly set things up first time
            createHome = true;
            isSystemUser = true;
          };

          users.groups.mariadb = { };

          flyingcircus.passwordlessSudoRules = [
            # Service users may switch to the mariadb system user
            {
              commands = [ "ALL" ];
              groups = [
                "sudo-srv"
                "service"
              ];
              runAs = "mariadb";
            }
          ];

          systemd.tmpfiles.rules = [
            "d /var/log/mariadb 0755 mariadb service 90d"
            "f /var/log/mariadb/mariadb.slow 0640 mariadb service -"
            # Cleanup files that are not required anymore and confusing
            "r /root/.my.cnf"
            "r ${toString localConfigPath}/mariadb.passwd"
          ];

          # Note that this does not use platform defaults, by using priority 100.
          # postrotate command taken from https://www.percona.com/blog/2013/04/18/rotating-mysql-slow-logs-safely/
          services.logrotate.settings = {
            "/var/log/mariadb/mariadb.slow" = {
              priority = 100;
              rotate = 10;
              frequency = "weekly";
              maxsize = "2G";
              compress = true;
              create = "0640 mariadb service";
              postrotate = ''
                ${package}/bin/mariadb -e \
                      'select @@global.long_query_time into @lqt_save; set global long_query_time=1.9; select sleep(2); FLUSH LOGS; select sleep(2); set global long_query_time=@lqt_save;'
              '';
              missingok = true;
            };
          };

          services.mysql = {
            enable = true;
            inherit package;
            user = "mariadb";
            dataDir = "/srv/mariadb";
            configFile =
              let
                cfg = config.services.mysql;
                format = lib.generators.toINI { listsAsDuplicateKeys = true; };
              in
              builtins.toFile "my.cnf" (
                (format cfg.settings)
                + (lib.optionalString (pathExists localConfigPath) ''
                  !includedir ${localConfigPath}
                '')
              );
            settings =
              let
                charset = "utf8mb4";
                collation = "utf8mb4_unicode_ci";
              in
              {
                mysqld = {
                  default-storage-engine = "innodb";
                  skip-external-locking = true;
                  skip-name-resolve = true;
                  max_allowed_packet = "512M";
                  bulk_insert_buffer_size = "128M";
                  tmp_table_size = "512M";
                  max_heap_table_size = "512M";
                  lower-case-table-names = "0";
                  max_connect_errors = "20";
                  default_storage_engine = "InnoDB";
                  table_definition_cache = "512";
                  open_files_limit = "65535";
                  sysdate-is-now = "ON";
                  sql_mode = "NO_ENGINE_SUBSTITUTION";

                  log_slow_verbosity = "full";
                  slow_query_log = "ON";
                  long_query_time = "0.1";
                  log_slow_slave_statements = "ON";
                  slow_query_log_file = "/var/log/mariadb/mariadb.slow";
                  log_slow_admin_statements = "ON";

                  init-connect = "SET NAMES ${charset} COLLATE ${collation}";
                  character-set-server = "${charset}";
                  collation-server = "${collation}";
                  character_set_server = "${charset}";
                  collation_server = "${collation}";

                  interactive_timeout = "28800";
                  wait_timeout = "28800";
                  connect_timeout = "10";

                  bind-address = "${lib.concatStringsSep "," cfg.listenAddresses}";

                  max_connections = "1000";
                  thread_cache_size = "128";
                  myisam-recover-options = "FORCE";
                  key_buffer_size = "64M";
                  table_open_cache = "1000";
                  # myisam-recover = "FORCE";

                  # * InnoDB
                  innodb_buffer_pool_size = "${toString (current_memory * cfg.bufferMemoryPercentage / 100)}M";
                  innodb_log_buffer_size = "64M";
                  innodb_file_per_table = "1";
                  innodb_read_io_threads = "${toString (cores * 4)}";
                  innodb_write_io_threads = "${toString (cores * 4)}";
                  # Percentage. Probably needs local tuning depending on the workload.
                  innodb_doublewrite = "1";
                  innodb_log_file_size = "512M";
                  innodb_flush_method = "O_DSYNC";
                  innodb_open_files = "800";
                  innodb_stats_on_metadata = "0";
                  innodb_lock_wait_timeout = "120";
                };

                mysqldump = {
                  quick = true;
                  quote-names = true;
                  max_allowed_packet = "512M";
                };

                isamchk.key_buffer = "16M";
              };

            ensureUsers = [
              {
                name = "sensuclient";
                ensurePermissions = {
                  "sensuclient.*" = "SELECT";
                };
              }
              {
                name = "telegraf";
                ensurePermissions = {
                  "telegraf.*" = "SELECT";
                };
              }
              {
                name = "mariadb";
                ensurePermissions = {
                  "*.*" = "ALL PRIVILEGES";
                };
              }
            ];

            ensureDatabases = [
              "sensuclient"
              "telegraf"
            ];
          };

          flyingcircus.localConfigDirs.mariadb = {
            dir = (toString localConfigPath);
            user = "mariadb";
          };

          environment.etc."local/mariadb/README.txt".text = ''
            MariaDB (${package.name}) is running on this machine.

            The root user is authenticated by socket auth with the `mariadb` and `root` system users.
            If you want to add a password to this user, you can do this manually with interactive
            SQL commands.

            Config files from this directory (/etc/local/mariadb) are included in the
            mariadb configuration. To set custom options, add a `local.cnf`
            (or any other *.cnf) file here, and run `sudo fc-manage switch`.

            ATTENTION: Changes to *.cnf files in this directory will restart MariaDB
            to activate the new configuration.

            For more information, see our documentation at
            ${fclib.roleDocUrl "mariadb"}
          '';

          systemd.services.mysql.serviceConfig.ReadWritePaths = [ "/var/log/mariadb" ];

          services.udev.extraRules = ''
            # increase readahead for mariadb
            SUBSYSTEM=="block", ACTION=="add|change", KERNEL=="vd[a-z]", ATTR{bdi/read_ahead_kb}="1024", ATTR{queue/read_ahead_kb}="1024"
          '';

          flyingcircus.services = {
            sensu-client.checks.mariadb = {
              notification = "MariaDB alive";
              command = mariadbCheck;
            };

            telegraf.inputs.mysql = [
              {
                servers = [ "telegraf@unix(/run/mysqld/mysqld.sock)/?tls=false" ];
              }
            ];
          };
        }

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
            reloadTriggers = [ config.environment.etc."alloy/mariadb_slowlog.alloy".source ];
            serviceConfig.SupplementaryGroups = [ "service" ];
          };

          environment.etc."alloy/mariadb_slowlog.alloy".text = ''
            local.file_match "mariadb_slowlogs" {
                path_targets = [{
                    __path__ = "/var/log/mysql/mysql.slow",
                    job_name = "mariadb/slowlogs",
                }]
            }

            loki.source.file "mariadb_slowlogs" {
                targets    = local.file_match.mariadb_slowlogs.targets
                forward_to = [loki.process.mariadb_slowlogs.receiver]
            }

            loki.process "mariadb_slowlogs" {
                forward_to = [loki.write.fcio_rg_loki.receiver]

                stage.multiline {
                    firstline = "^# Time:"
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
                          "Time: (?P<time>[0-9: ]+)"
                          "User@Host: (?P<user>\\S+) @ (?P<host>\\S+)"
                          "Schema:\\s+(?P<schema>\\S*?)?"
                          "Query_time:\\s+(?P<query_time>\\S+)"
                          "Lock_time:\\s+(?P<lock_time>[0-9.]+)"
                          "Rows_sent:\\s+(?P<rows_sent>\\d+)"
                          "Rows_examined:\\s+(?P<rows_examined>\\d+)"
                          "Rows_affected:\\s+(?P<rows_affected>\\d+)"
                          "Bytes_sent:\\s+(?P<bytes_sent>\\d+)"
                          "SET timestamp=\\d+;"
                          "\\n(?P<query>[^#](?s:.+))"
                        ])
                      )
                    }"
                }

                stage.timestamp {
                    source = "time"
                    format = "060102 15:04:05"
                    location = "CET"
                }

                stage.structured_metadata {
                  values = {
                    user = "",
                    host = "",
                    schema = "",
                    query_time = "",
                    lock_time = "",
                    rows_sent = "",
                    rows_examined = "",
                    rows_affected = "",
                    bytes_sent = "",
                  }
                }

                stage.output {
                    source = "query"
                }
            }
          '';
        })
      ]
    );
}
