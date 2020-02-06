{ config, pkgs, lib, ... }:
let
  roles = config.flyingcircus.roles;
in {
  options = {
    # redis4 is an alias for redis, see rename.nix
    flyingcircus.roles.redis.enable =
      lib.mkEnableOption "Flying Circus Redis";
  };

  config = {
      flyingcircus.services.redis.enable = roles.redis.enable;
      flyingcircus.roles.statshost.globalAllowedMetrics = [ "redis" ];
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        {
          regex = "aof_last_bgrewrite_status|aof_last_write_status|maxmemory_policy|rdb_last_bgsave_status|used_memory_dataset_perc|used_memory_peak_perc";
          action = "drop";
        }
      ];
    };
}
