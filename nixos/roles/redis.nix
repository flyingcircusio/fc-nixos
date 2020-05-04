{ config, pkgs, lib, ... }:
let
  role = config.flyingcircus.roles.redis;

in {
  options = {
    # redis4 is an alias for redis, see rename.nix
    flyingcircus.roles.redis.enable =
      lib.mkEnableOption "Flying Circus Redis";
  };

  config = lib.mkIf role.enable {
    flyingcircus.services.redis.enable = true;
  };
}
