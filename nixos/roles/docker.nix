{ config, lib, pkgs, ... }:
{
  options = {
    flyingcircus.roles.docker = {
      enable = lib.mkEnableOption "Enable Docker";
    };
  };

  config = lib.mkIf config.flyingcircus.roles.docker.enable {
    environment.systemPackages = [ pkgs.docker-compose ];
    flyingcircus.users.serviceUsers.extraGroups = [ "docker" ];
    virtualisation.docker.enable = true;
  };

}
