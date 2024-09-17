{ config, lib, pkgs, ... }:

let
  cfg = config.flyingcircus.roles.loki;
  fclib = config.fclib;
in
{
  options = with lib; {
    flyingcircus.roles.loki = {
      enable = mkEnableOption "Flying Circus Grafana Loki server";
      supportsContainers = fclib.mkEnableContainerSupport;
      logRetentionPeriod = mkOption {
        type = types.ints.unsigned;
        default = 30;
        description = "Global retention period for log data in days. Setting to zero disables automatic log expiry";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.loki = {
      enable = true;
      configuration = {
        server.http_listen_address = "127.0.0.1";

        auth_enabled = false;

        schema_config.configs = [{
          from = "2024-09-10";
          store = "tsdb";
          object_store = "filesystem";
          schema = "v13";
          # default values in loki 3.1.1, here specified explicitly
          index.prefix = "";
          index.path_prefix = "index/";
          index.period = "24h";
        }];

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
          retention_period = (builtins.toString cfg.logRetentionPeriod) + "d";
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
