{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.flyingcircus.roles.loki;
  fclib = config.fclib;

  storageScheduleSubmodule =
    with lib;
    with types;
    submodule {
      options = {
        startDate = mkOption {
          type = strMatching "[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}";
        };
        backend = mkOption {
          type = enum [
            "filesystem"
            "aws"
          ];
        };
        schemaVersion = mkOption {
          type = ints.positive;
          default = 13;
        };
      };
    };

  renderStorageSchema = opts: {
    from = opts.startDate;
    # always tsdb for index tables
    store = "tsdb";
    schema = "v${toString opts.schemaVersion}";
    # default values in loki 3.1.1, here specified explicitly
    index.prefix = "";
    index.path_prefix = "index/";
    index.period = "24h";

    object_store = opts.backend;
  };
in
{
  options = with lib; {
    flyingcircus.roles.loki = {
      enable = mkEnableOption "the Flying Circus Grafana Loki server";
      supportsContainers = fclib.mkEnableDevhostSupport;

      logRetentionPeriod = mkOption {
        type = types.ints.unsigned;
        default = 30;
        description = "Global retention period for log data in days. Setting to zero disables automatic log expiry";
      };

      s3 = mkOption {
        description = "Configure log storage in S3-compatible object store";
        default = { };
        type = types.submodule {
          options = {
            enable = mkOption {
              description = ''
                Enable additional configuration so that loki's logs can be stored in
                object storage.

                This option merely serves as a toggle for the configuration that enables
                storing logs in object storage and does not affect the actual storage backend.
                If you just want to store logs on disk instead you should add a fitting
                entry to `flyingcircus.roles.loki.storageSchedule` instead.
              '';
              default = config.flyingcircus.enc ? role_configuration.loki;
              # role_configuration.loki is available to VMs managed via the directory with the loki role.
              # The defaultText is adjusted here because the value above evaluates to false when
              # evaluating the options for fc-search etc.
              defaultText = "true";
            };
            endpoint = mkOption {
              description = "HTTP(S) endpoint of the object store";
              type = types.str;
              default = "http://rgw.local:7480";
              defaultText = "<local rgw address>";
            };
            bucketName = fclib.mkRoleOption "loki" {
              description = "S3 bucket name";
              type = types.str;
              default = c: c.object_store_bucket;
            };
          };
        };
      };

      storageSchedule = mkOption {
        description = "Log storage schedule configuration";
        default = { };
        type =
          with types;
          submodule {
            options = {
              default = mkOption {
                visible = false;
                type = listOf storageScheduleSubmodule;
                default = [
                  {
                    startDate = "2024-09-10";
                    backend = "filesystem";
                  }
                  {
                    startDate = "2026-07-01";
                    backend = "aws";
                  }
                ];
              };
              extra = mkOption {
                description = ''
                  Entries to add to the log storage schedule.

                  The default policy is to store all logs in object storage starting on 2026-07-01.
                  Object storage buckets and credentials are set up automatically for you.

                  If you instead wish to store logs on the filesystem, add an entry here
                  with `backend = "filesystem";` and a `startDate` in the future.

                  See https://grafana.com/docs/loki/latest/operations/storage/schema/ for more details.
                '';
                type = listOf storageScheduleSubmodule;
                default = [ ];
                defaultText = "[]";
              };
            };
          };
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.etc."local/loki/README.txt".text = ''
          This is a stub README for the Loki role.
        '';

        services.loki = {
          enable = true;
          configuration = {
            server.http_listen_address = "127.0.0.1";

            auth_enabled = false;

            schema_config.configs = map renderStorageSchema (
              cfg.storageSchedule.default ++ cfg.storageSchedule.extra
            );

            storage_config = {
              # index file management
              tsdb_shipper = {
                active_index_directory = "/var/lib/loki/tsdb-shipper-index";
                cache_location = "/var/lib/loki/tsdb-shipper-cache";
              };
              # log data configuration
              filesystem.directory = "/var/lib/loki/chunk-store";
            };
            compactor = {
              working_directory = "/var/lib/loki/compactor-workdir";
              retention_enabled = true;
              delete_request_store = "filesystem";
            };

            limits_config = {
              retention_period = (toString cfg.logRetentionPeriod) + "d";
            };

            # configuration stubs for multi-process management plane
            common = {
              replication_factor = 1;
              ring.kvstore.store = "inmemory";
            };
          };
        };

        flyingcircus.services.nginx = {
          enable = true;
          virtualHosts.loki = {
            serverName = config.networking.hostName;
            serverAliases = [
              (fclib.fqdn { vlan = "srv"; })
              "${config.networking.hostName}.${config.networking.domain}"
            ];
            listen = builtins.map (addr: {
              inherit addr;
              port = 3100;
            }) fclib.network.srv.dualstack.addressesQuoted;
            locations."/" = {
              proxyPass = "http://127.0.0.1:3100";
              proxyWebsockets = true;
            };
          };
        };
      }

      (lib.mkIf cfg.s3.enable (
        let
          credentialFile = "/run/loki/s3-env";
        in
        {
          services.loki.configuration.storage_config = {
            aws = {
              # authentication configured separately
              endpoint = cfg.s3.endpoint;
              bucketnames = cfg.s3.bucketName;
              s3forcepathstyle = true;
            };
          };

          users.groups.lokienv = { };

          systemd.tmpfiles.rules = [
            "d '/run/loki' 0750 root lokienv - -"
            "Z '/run/loki' 0750 root lokienv - -"
          ];

          systemd.services.loki.serviceConfig = {
            EnvironmentFile = credentialFile;
            SupplementaryGroups = [ "lokienv" ];
          };

          systemd.services.loki-s3-setup = {
            wantedBy = [ "loki.service" ];
            before = [ "loki.service" ];

            script = ''
              if [ -z $AWS_ACCESS_KEY_ID ]; then
                AWS_ACCESS_KEY_ID=$(cat ${config.flyingcircus.encPath} | ${lib.getExe pkgs.jq} -r '.role_configuration.loki.object_store_access_key')
              fi
              if [ -z $AWS_SECRET_ACCESS_KEY ]; then
                AWS_SECRET_ACCESS_KEY=$(cat ${config.flyingcircus.encPath} | ${lib.getExe pkgs.jq} -r '.role_configuration.loki.object_store_secret_key')
              fi

              export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
              ${pkgs.awscli2}/bin/aws s3 --endpoint-url ${cfg.s3.endpoint} mb s3://${cfg.s3.bucketName} --region ""

              # https://github.com/grafana/loki/blob/main/operator/internal/manifests/storage/var.go#L5
              cat >${credentialFile} <<EOF
              AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
              AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
              EOF

              chown :lokienv ${credentialFile}
            '';

            serviceConfig = {
              Type = "oneshot";
              User = "root";
            };
          };
        }
      ))
    ]
  );
}
