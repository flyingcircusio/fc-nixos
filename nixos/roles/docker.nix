{ config, lib, pkgs, ... }:

let
  fclib = config.fclib;
in
{
  options = {
    flyingcircus.roles.docker = {
      enable = lib.mkEnableOption "Enable Docker";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = lib.mkIf config.flyingcircus.roles.docker.enable {
    environment.systemPackages = [ pkgs.docker-compose ];
    flyingcircus.users.serviceUsers.extraGroups = [ "docker" ];
    virtualisation.docker.enable = true;
  };

}
