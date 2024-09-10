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
        # XXX loki only uses a single listen address.
        server.http_listen_address = builtins.head fclib.network.srv.v4.addresses;

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
  };
}
