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

    networking.firewall.extraCommands = ''
      # Allow BFD
      ip6tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p udp --dport 3784 -j nixos-fw-accept
      ip6tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p udp --dport 3785 -j nixos-fw-accept
      # Allow BGP
      ip6tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p tcp --dport 179 -j nixos-fw-accept
    '';

  };
}
