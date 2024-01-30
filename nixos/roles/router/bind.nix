{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
in
lib.mkIf role.enable {
  services.bind = {
    enable = true;
  };
}
