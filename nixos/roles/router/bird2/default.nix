{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;

let
  inherit (config) fclib;
  role = config.flyingcircus.roles.router;
  inherit (config.flyingcircus) location static;
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

  routerId =
    static.routerIdSources.host."${config.networking.hostName}" or (
      let
        network = static.routerIdSources.location."${location}";
      in
      head fclib.network."${network}".v4.addresses
    );

  commonConfig = ''
    log syslog all;

    router id ${routerId};

    ipv4 table master4;
    ipv6 table master6;

    # Flag for operating BGP session migration from NixOS config
    define MIGRATION_STATE=${toString role.migrationState};
  '';
in
{
  options.flyingcircus.roles.router.migrationState = lib.mkOption {
    type = lib.types.ints.unsigned;
    default = 0;
  };

  config = lib.mkIf role.enable {
    services.bird = {
      enable = true;
      package = pkgs.bird2;
      config = lib.concatStringsSep "\n\n" [
        (if role.isPrimary then primaryConfig else secondaryConfig)
        commonConfig
        locationConfig
      ];
    };

    networking.firewall.extraCommands =
      let
        bgpNetworks =
          (fclib.filterConfiguredNetworks static.routerUplinkNetworks."${location}")
          ++ (static.routerDownlinkNetworks."${location}" or [ ]);
        bgpInterfaces = map (network: fclib.network."${network}".interface) bgpNetworks;
      in
      ''
        # Allow BFD and BGP
      ''
      + (lib.concatMapStringsSep "\n" (iface: ''
        ip46tables -A nixos-fw -i ${iface} -p udp --dport 3784 -j nixos-fw-accept
        ip46tables -A nixos-fw -i ${iface} -p udp --dport 3785 -j nixos-fw-accept
        ip46tables -A nixos-fw -i ${iface} -p tcp --dport 179 -j nixos-fw-accept
      '') bgpInterfaces);
  };

}
