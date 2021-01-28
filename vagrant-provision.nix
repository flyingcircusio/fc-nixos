{ config, lib, pkgs, ... }:
let
in {
  networking.interfaces = lib.mkForce {
    ethsrv.ipv4.addresses = [ { address = "192.168.12.146"; prefixLength = 24; } ];
    ethfe.ipv4.addresses = [ { address = "192.168.13.146"; prefixLength = 24; } ];
  };

  users.users.s-serviceuser = {
    home = "/srv/s-serviceuser/";
    isNormalUser = true;
    extraGroups = [ "service" ];
  };
}
