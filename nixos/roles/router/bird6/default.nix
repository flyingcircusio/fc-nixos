{ config, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  inherit (config.flyingcircus) location;
  locationConfig = readFile (./. + "/${location}.conf");

  primaryConfig = ''
    # Config for a primary router.
    define PRIMARY=1;
    define UPLINK_MED=0;
  '';

  secondaryConfig = ''
    # Config for a secondary router.
    define PRIMARY=0;
    define UPLINK_MED=500;
  '';

  routerId = head fclib.network.tr.v4.addresses;

  commonConfig = ''
    log syslog all;

    # Keep router ID in sync between v4 and v6
    router id ${routerId};
  '';
in
{
  config = lib.mkIf role.enable {
    services.bird6 = {
      enable = true;
      config = lib.concatStringsSep "\n\n" [
        (if role.isPrimary then primaryConfig else secondaryConfig)
        commonConfig
        locationConfig
      ];
    };
  };
}
