{ config, lib, pkgs, ... }:

with builtins;

let
  inherit (config) fclib;
  cfg = config.flyingcircus.roles.ferretdb;
in
{
  options = with lib; {
    flyingcircus.roles.ferretdb = {
      enable = mkEnableOption "Enable the ferretdb role, a (mostly) drop-in replacement for MongoDB";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = lib.mkIf cfg.enable {
    flyingcircus.services.ferretdb.enable = true;
  };
}
