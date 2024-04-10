{ config, pkgs, lib, ... }:

with builtins;

let
  inherit (config) fclib;
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

  networking.firewall.extraCommands = ''
    ip46tables -A nixos-fw -i ethtr+ -p udp --dport 123 -j REJECT
    ip46tables -A nixos-fw -p udp --dport 123 -j ACCEPT
  '';

}
