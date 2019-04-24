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
    };
}
