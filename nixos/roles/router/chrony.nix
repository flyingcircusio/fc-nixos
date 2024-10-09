{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
  inherit (config.flyingcircus) location static;
  role = config.flyingcircus.roles.router;
in
lib.mkIf role.enable {
  services.chrony = {
    enable = true;

    serverOption = "iburst";

    extraConfig = ''
      minsources 3
      maxchange 100 0 0
      makestep 0.001 1
      maxdrift 100
      maxslewrate 100
      rtcsync

      ${lib.concatStringsSep "\n" (map (n: "allow ${n};") fclib.networks.all)}

    '';
  };

  networking.firewall.extraCommands = let
    uplinkNetworks = static.routerUplinkNetworks."${location}";
    uplinkIfaces = map (network: fclib.network."${network}".interface) uplinkNetworks;
  in
    (lib.concatMapStringsSep "\n" (iface:
      "ip46tables -A nixos-fw -i ${iface} -p udp --dport 123 -j REJECT"
    ) uplinkIfaces)
    + "\n" + "ip46tables -A nixos-fw -p udp --dport 123 -j ACCEPT";

  services.timesyncd.enable = false;

}
