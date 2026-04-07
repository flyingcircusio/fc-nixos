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

  defaultRouterId =
    static.routerIdSources.host."${config.networking.hostName}" or (
      let
        network = static.routerIdSources.location."${location}";
      in
      head fclib.network."${network}".v4.addresses
    );

  hostConfig = role.extraBirdConfig;

  commonConfig = ''
    log syslog all;

    router id ${role.routerId};

    ipv4 table master4;
    ipv6 table master6;
  '';

  migrationCompatConfig = ''
    # Flag for operating BGP session migration from NixOS config
    define MIGRATION_STATE=${toString role.migrationState};
  '';
in
{
  options.flyingcircus.roles.router = with lib; {
    migrationState = mkOption {
      type = types.ints.unsigned;
      default = 0;
    };
    extraBirdConfig = mkOption {
      type = types.lines;
      default = "";
    };

    birdConfig = mkOption {
      type = types.lines;
      description = ''
        Bird configuration for this router.

        This will be appended to a standard snippet, which defines:
        - Constants indicating whether this router is currently the primary or secondary
          router, and the MED which should be applied to routes advertised to upstream
          networks.
        - Common logging options.
        - The router ID.
        - Routing tables for IPv4 and IPv6 unicast routes.
      '';
      default = lib.concatStringsSep "\n\n" [
        migrationCompatConfig
        hostConfig
        # evaluate to empty string if location not set
        (lib.optionalString (location != "standalone") locationConfig)
      ];
    };

    routerId = mkOption {
      type = types.addCheck types.str fclib.isIp4;
      description = "Router ID for this router";
      default = if location == "standalone" then "0.0.0.0" else defaultRouterId;
    };
  };

  config = lib.mkIf role.enable {
    services.bird = {
      enable = true;
      package = pkgs.bird2;
      config = lib.concatStringsSep "\n\n" [
        (if role.isPrimary then primaryConfig else secondaryConfig)
        commonConfig
        role.birdConfig
      ];
    };

    networking.firewall.extraCommands =
      let
        bgpNetworks =
          (fclib.filterConfiguredNetworks role.routerUplinkNetworks) ++ role.routerDownlinkNetworks;
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
