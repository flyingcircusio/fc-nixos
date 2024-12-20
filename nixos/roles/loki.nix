{ config, lib, pkgs, ... }:

let
  cfg = config.flyingcircus.roles.loki;
  fclib = config.fclib;

  storageScheduleSubmodule = with lib; with types; submodule {
    options = {
      startDate = mkOption {
        type = strMatching "[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}";
      };
      backend = mkOption { type = enum [ "filesystem" "s3" ]; };
      schemaVersion = mkOption { type = ints.positive; default = 13; };
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
      enable = mkEnableOption "Flying Circus Grafana Loki server";
      supportsContainers = fclib.mkEnableDevhostSupport;

      logRetentionPeriod = mkOption {
        type = types.ints.unsigned;
        default = 30;
        description = "Global retention period for log data in days. Setting to zero disables automatic log expiry";
      };

      s3 = mkOption {
        description = "Configure log storage in S3-compatible object store";
        default = {};
        type = types.submodule {
          options = {
            enable = mkEnableOption "store log data in S3";
            endpoint = mkOption {
              description = "HTTP(S) endpoint of S3 storage server";
              type = types.str;
              default = "http://rgw.local:7840";
            };
            bucketName = mkOption {
              description = "S3 bucket name";
              type = types.str;
            };
            credentialFile = mkOption {
              description = "Path to file containing credentials used for authenticating to the S3 server (must be readable by the loki user)";
              type = types.path;
              default = "/etc/local/loki/s3.cfg";
            };
          };
        };
      };

      storageSchedule = mkOption {
        description = "Log storage schedule configuration";
        default = {};
        type = with types; submodule {
          options = {
            default = mkOption {
              visible = false;
              type = listOf storageScheduleSubmodule;
              default = [{ startDate = "2024-09-10"; backend = "filesystem"; }];
            };
            extra = mkOption {
              description = "Additional entries to add to the log storage schedule";
              type = listOf storageScheduleSubmodule;
              default = [];
              defaultText = "[]";
            };
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."local/loki/README.txt".text = ''
      This is a stub README for the Loki role.
    '';

    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_address = "127.0.0.1";

        auth_enabled = false;

        schema_config.configs = map renderStorageSchema
          (cfg.storageSchedule.default ++ cfg.storageSchedule.extra);

        storage_config = {
          # index file management
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-shipper-index";
            cache_location = "/var/lib/loki/tsdb-shipper-cache";
          };
          # log data configuration
          filesystem.directory = "/var/lib/loki/chunk-store";
        } // lib.optionalAttrs (cfg.s3.enable) {
          s3 = {
            # authentication configured separately
            endpoint = cfg.s3.endpoint;
            bucketNames = cfg.s3.bucketNames;
            s3forcepathstyle = true;
          };
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

    systemd.services.loki.serviceConfig = lib.mkIf (cfg.s3.enable) {
      Environment = "AWS_SHARED_CREDENTIALS_FILE=${cfg.s3.credentialFile}";
    };

    flyingcircus.services.nginx = {
      enable = true;
      virtualHosts."${config.networking.hostName}" = {
        serverAliases = [
          (fclib.fqdn { vlan = "srv"; })
          "${config.networking.hostName}.${config.networking.domain}"
        ];
        listen = builtins.map (addr: { inherit addr; port = 3100; })
          fclib.network.srv.dualstack.addressesQuoted;
        locations = with builtins; with lib; let
          proxyConfig = { proxyPass = "http://127.0.0.1:3100"; };
        in listToAttrs (
          [(nameValuePair "/" { extraConfig = "return 403;"; })] ++
          (map (path: nameValuePair path proxyConfig) [
            # https://grafana.com/docs/loki/latest/reference/loki-http-api/

            # ingestion endpoints
            "/loki/api/v1/push"
            "/otlp/v1/logs"

            # query endpoints
            "/loki/api/v1/query"
            "/loki/api/v1/query_range"
            "/loki/api/v1/labels"
            "/loki/api/v1/label"
            "/loki/api/v1/series"
            "/loki/api/v1/index/stats"
            "/loki/api/v1/index/volume"
            "/loki/api/v1/index/volume_range"
            "/loki/api/v1/patterns"
            "/loki/api/v1/tail"
          ])
        );
      };
    };
  };
}
