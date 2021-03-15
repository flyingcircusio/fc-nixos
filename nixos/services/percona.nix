{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.percona;

  mysql = cfg.package;

  initFile = "/run/mysqld/init_set_root_password.sql";

  pidFile = "${cfg.pidDir}/mysqld.pid";

  mysqldOptions =
    "--user=${cfg.user} --datadir=${cfg.dataDir} --basedir=${mysql} --init-file=${initFile}";

  myCnf = pkgs.writeText "my.cnf"
  ''
    [mysqld]
    port = ${toString cfg.port}
    ${optionalString
      (cfg.replication.role == "master" || cfg.replication.role == "slave")
      "log-bin=mysql-bin"}
    ${optionalString
      (cfg.replication.role == "master" || cfg.replication.role == "slave")
      "server-id = ${toString cfg.replication.serverId}"}
    ${cfg.extraOptions}
  '';

  mysqlInit =
  if versionAtLeast mysql.mysqlVersion "5.7" then
    "${mysql}/bin/mysqld --initialize-insecure ${mysqldOptions}"
  else
    "${pkgs.perl}/bin/perl ${mysql}/bin/mysql_install_db ${mysqldOptions}";

  setPasswordSql =
    if (lib.versionAtLeast mysql.mysqlVersion "5.7") then
      "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY \'$pw\';"
    else
      "SET PASSWORD FOR 'root'@'localhost' = PASSWORD(\'$pw\');";

  mysqlPreStart = ''
    umask 0066

    mkdir -p /run/mysqld
    chmod 0755 /run/mysqld
    chown -R ${cfg.user} /run/mysqld

    # Generate mysql root password file if it's not present.
    if [[ ! -f ${cfg.rootPasswordFile} ]]; then
      pw=`${pkgs.apg}/bin/apg -a 1 -M lnc -n 1 -m 12`
      echo -n "''${pw}" > ${cfg.rootPasswordFile}
    fi
    chown root:service ${cfg.rootPasswordFile}
    chmod 660 ${cfg.rootPasswordFile}

    pw=$(<${cfg.rootPasswordFile})
    cat > /root/.my.cnf <<__EOT__
    # Do not modify this file, it will be overwritten when MySQL starts!
    # The following options will be passed to all MySQL clients
    [client]
    password = ''${pw}
    user = root
    __EOT__
    chmod 440 /root/.my.cnf

    # write init file for mysqld to set the root password
    cat > ${initFile} <<__EOT__
    ${setPasswordSql}
    __EOT__
    chmod 440 ${initFile}
    chown ${cfg.user} ${initFile}

    if ! test -e ${cfg.dataDir}/mysql; then
        mkdir -m 0700 -p ${cfg.dataDir}
        chown -R ${cfg.user} ${cfg.dataDir}
        ${mysqlInit}
        touch /run/mysql_init
    fi

    mkdir -m 0755 -p ${cfg.pidDir}
    chown -R ${cfg.user} ${cfg.pidDir}
  '';

in

{
  ###### interface

  options = {
    services.percona = {

      enable = mkOption {
        default = false;
        description = "
          Whether to enable the MySQL server.
        ";
      };

      package = mkOption {
        type = types.package;
        example = literalExample "pkgs.percona";
        description = "
          Which MySQL derivation to use.
        ";
      };

      port = mkOption {
        default = "3306";
        description = "Port of MySQL";
      };

      user = mkOption {
        default = "mysql";
        description = "User account under which MySQL runs";
      };

      dataDir = mkOption {
        default = "/srv/mysql";
        description = "Location where MySQL stores its table files";
      };

      rootPasswordFile = mkOption {
        description = "Location of the root password file";
      };

      pidDir = mkOption {
        default = "/run/mysqld";
        description = "Location of the file which stores the PID of the MySQL server";
      };

      extraOptions = mkOption {
        default = "";
        example = ''
          key_buffer_size = 6G
          table_cache = 1600
          log-error = /var/log/mysql_err.log
        '';
        description = ''
          Provide extra options to the MySQL configuration file.

          Please note, that these options are added to the
          <literal>[mysqld]</literal> section so you don't need to explicitly
          state it again.
        '';
      };

      initialDatabases = mkOption {
        default = [];
        description = ''
          List of database names and their initial schemas that should be used
          to create databases on the first startup of MySQL
        '';
        example = [
          { name = "foodatabase"; schema = literalExample "./foodatabase.sql"; }
          { name = "bardatabase"; schema = literalExample "./bardatabase.sql"; }
        ];
      };

      initialScript = mkOption {
        default = null;
        description = ''
          A file containing SQL statements to be executed on the first startup.
          Can be used for granting certain permissions on the database
        '';
      };

      replication = {
        role = mkOption {
          default = "none";
          description = ''
            Role of the MySQL server instance. Can be either: master, slave or
            none
          '';
        };

        serverId = mkOption {
          default = 1;
          description = ''
            Id of the MySQL server instance. This number must be unique for each
            instance
          '';
        };

        masterHost = mkOption {
          description = "Hostname of the MySQL master server";
        };

        masterUser = mkOption {
          description = "Username of the MySQL replication user";
        };

        masterPassword = mkOption {
          description = "Password of the MySQL replication user";
        };

        masterPort = mkOption {
          default = 3306;
          description = "Port number on which the MySQL master server runs";
        };
      };
    };

  };


  ###### implementation

  config = mkIf config.services.percona.enable {

    users.extraUsers.mysql = {
      description = "MySQL server user";
      group = "mysql";
      uid = config.ids.uids.mysql;
    };

    users.extraGroups.mysql.gid = config.ids.gids.mysql;

    environment.systemPackages = [ mysql ];

    systemd.services.mysql = {
      description = "MySQL Server";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = "${cfg.dataDir}";

      serviceConfig = {
        ExecStart = "${mysql}/bin/mysqld --defaults-extra-file=${myCnf} ${mysqldOptions}";
        Restart = "always";
        TimeoutSec = 360;
      };

      preStart = mysqlPreStart;
      postStart =
        ''
          # Wait until the MySQL server is available for use
          count=0
          while [ ! -e /run/mysqld/mysqld.sock ]
          do
              if [ $count -eq 300 ]
              then
                  echo "Tried 300 seconds, giving up..."
                  exit 1
              fi

              echo "No MySQL server contact after $count attempts. Waiting..."
              count=$((count+1))
              sleep 3
          done

          if [ -f /run/mysql_init ]
          then
              ${concatMapStrings (database:
                ''
                  # Create initial databases
                  if ! test -e "${cfg.dataDir}/${database.name}"; then
                      echo "Creating initial database: ${database.name}"
                      ( echo "create database ${database.name};"
                        echo "use ${database.name};"

                        if [ -f "${database.schema}" ]
                        then
                            cat ${database.schema}
                        elif [ -d "${database.schema}" ]
                        then
                            cat ${database.schema}/mysql-databases/*.sql
                        fi
                      ) | ${mysql}/bin/mysql -u root -N
                  fi
                '') cfg.initialDatabases}

              ${optionalString (cfg.replication.role == "slave")
                ''
                  # Set up the replication master

                  ( echo "stop slave;"
                    echo "change master to master_host='${cfg.replication.masterHost}', master_user='${cfg.replication.masterUser}', master_password='${cfg.replication.masterPassword}';"
                    echo "start slave;"
                  ) | ${mysql}/bin/mysql -u root -N
                ''}

              ${optionalString (cfg.initialScript != null)
                ''
                  # Execute initial script
                  cat ${cfg.initialScript} | ${mysql}/bin/mysql -u root -N
                ''}

            rm /run/mysql_init
          fi
        '';  # */
      };
  };
}
