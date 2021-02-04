{ config, lib, pkgs, ... }:
let
in {
  networking.interfaces = lib.mkForce {
    ethfe.ipv4.addresses = [ { address = "192.168.21.146"; prefixLength = 24; } ];
    ethsrv.ipv4.addresses = [ { address = "192.168.31.146"; prefixLength = 24; } ];
  };

  users.users.s-serviceuser = {
    home = "/srv/s-serviceuser/";
    isNormalUser = true;
    extraGroups = [ "service" ];
  };
}
