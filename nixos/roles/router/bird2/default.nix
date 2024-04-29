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

    router id ${routerId};

    ipv4 table master4;
    ipv6 table master6;
  '';
in
{
  config = lib.mkIf role.enable {
    services.bird2 = {
      enable = true;
      config = lib.concatStringsSep "\n\n" [
        (if role.isPrimary then primaryConfig else secondaryConfig)
        commonConfig
        locationConfig
      ];
    };

    networking.firewall.extraCommands = ''
      # Allow BFD
      ip46tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p udp --dport 3784 -j nixos-fw-accept
      ip46tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p udp --dport 3785 -j nixos-fw-accept
      # Allow BGP
      ip46tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p tcp --dport 179 -j nixos-fw-accept
    '';

  };
}
