{ config, lib, ...}:

with builtins;

let

  role = config.flyingcircus.roles.router;
  inherit (config) fclib;
  blockIndent = width: text:
    let
      # Create a string of `width` number of spaces.
      spaces = lib.fixedWidthString width " " " ";
      lines = fclib.lines text;
    in
      fclib.unlines
        ([(head lines)] ++ (fclib.indentWith spaces (tail lines)));

  vlans =
    lib.filterAttrs
      (vlan: networkAttrs: networkAttrs != [])
      (lib.mapAttrs
        (vlan: interface:
          if lib.elem vlan ["lo" "ipmi" "tr" "sto" "stb"]
          then []
          else (filter (na: na.addresses != []) interface.v6.networkAttrs))
        fclib.network);

  mkPrefixBlock = { network, prefixLength, ... }: ''
    prefix ${network}/${toString prefixLength} {
      AdvOnLink on;
      AdvAutonomous on;
    };
  '';

  mkInterfaceBlock = vlan: networkAttrs:
    let
      interfaceName = if vlan == "ws" then "br${vlan}" else "eth${vlan}";
      prefixConfigurations = lib.concatMapStringsSep "\n\n" mkPrefixBlock networkAttrs;
    in ''
      # ${vlan} VLAN
      interface ${interfaceName} {
        AdvSendAdvert on;
        AdvOtherConfigFlag on;
        ${blockIndent 2 prefixConfigurations}
      };
    '';
in
{
  config = lib.mkIf role.enable {
    services.radvd = {
      enable = true;
      config = lib.concatStringsSep "\n\n" (lib.mapAttrsToList mkInterfaceBlock vlans);
    };
  };
}
