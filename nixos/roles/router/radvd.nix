{ config, lib, ... }:

with builtins;

let

  role = config.flyingcircus.roles.router;
  inherit (config) fclib;
  inherit (config.flyingcircus) location static;
  blockIndent =
    width: text:
    let
      # Create a string of `width` number of spaces.
      spaces = lib.fixedWidthString width " " " ";
      lines = lib.splitString "\n" text;
    in
    lib.concatStringsSep "\n" ([ (head lines) ] ++ (fclib.indentWith spaces (tail lines)));

  ifaces = listToAttrs (
    filter (iface: iface.value.networkAttrs != [ ]) (
      map (
        vlan:
        lib.nameValuePair vlan (
          let
            iface = fclib.network."${vlan}";
          in
          {
            inherit (iface) interface;
            networkAttrs = filter (attr: attr.addresses != [ ]) iface.v6.networkAttrs;
          }
        )
      ) role.routerGatewayNetworks
    )
  );

  mkPrefixBlock =
    { network, prefixLength, ... }:
    ''
      prefix ${network}/${toString prefixLength} {
        AdvOnLink on;
        AdvAutonomous on;
      };
    '';

  mkInterfaceBlock =
    vlan: iface:
    let
      prefixConfigurations = lib.concatMapStringsSep "\n\n" mkPrefixBlock iface.networkAttrs;
    in
    ''
      # ${vlan} network
      interface ${iface.interface} {
        AdvSendAdvert on;
        AdvOtherConfigFlag on;
        ${blockIndent 2 prefixConfigurations}
      };
    '';

in
{
  config = lib.mkIf (role.enable && role.isPrimary) {
    services.radvd = {
      enable = true;
      config = lib.concatStringsSep "\n\n" (lib.mapAttrsToList mkInterfaceBlock ifaces);
    };
  };
}
