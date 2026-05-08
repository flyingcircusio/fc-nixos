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

  commonConfig = ''
    log syslog all;

    router id ${role.routerId};

    ipv4 table master4;
    ipv6 table master6;
  '';
in
{
  options.flyingcircus.roles.router = with lib; {
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
      default = "";
    };

    routerId = mkOption {
      type = types.addCheck types.str fclib.isIp4;
      description = "Router ID for this router";
      default = if location == "standalone" then "0.0.0.0" else null;
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
