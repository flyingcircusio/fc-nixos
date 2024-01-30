{ config, lib, ...}:

with builtins;

let
  role = config.flyingcircus.roles.router;
  inherit (config) fclib;
in
{
  config = lib.mkIf role.enable {
    services.dhcpd4 = {
      enable = false;
    };

    services.dhcpd6 = {
      enable = false;
    };
  };
}
