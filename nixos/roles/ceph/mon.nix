{ config, lib, pkgs, ... }:

with builtins;

let
  fclib = config.fclib;
  role = config.flyingcircus.roles.ceph_osd;
  enc = config.flyingcircus.enc;

  ceph_sudo = pkgs.writeScriptBin "ceph-sudo" ''
    #! ${pkgs.stdenv.shell} -e
    exec /run/wrappers/bin/sudo ${pkgs.ceph}/bin/ceph "$@" 
  '';
in
{
  options = {
    flyingcircus.roles.ceph_mon = {
      enable = lib.mkEnableOption "CEPH Monitor";
    };
  };


  config = lib.mkIf role.enable {

    flyingcircus.services.ceph.server.enable = true;

    systemd.services.fc-ceph-mon = {
      description = "Start/stop local Ceph Mon (via fc-ceph)";
      wantedBy = [ "multi-user.target" ];


    }

  };
}
