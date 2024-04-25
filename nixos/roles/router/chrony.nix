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

  # The + on the tr interface is slightly muddy: this is an assumption that
  # all transfer interfaces are a) named tr<something> and b) consistently use
  # eth/br on the same machine (either everything bridged/through vxlan or all
  # directly on an ethernet link)
  networking.firewall.extraCommands = ''
    ip46tables -A nixos-fw -i ${fclib.network.tr.interface}+ -p udp --dport 123 -j REJECT
    ip46tables -A nixos-fw -p udp --dport 123 -j ACCEPT
  '';

  services.timesyncd.enable = false;

}
