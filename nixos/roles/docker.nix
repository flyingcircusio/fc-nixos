{ config, lib, ... }:
{
  options = {
    flyingcircus.roles.docker = {
      enable = lib.mkEnableOption "Enable Docker";
    };
  };

  config = lib.mkIf config.flyingcircus.roles.docker.enable {
    virtualisation.docker.enable = true;
    flyingcircus.users.serviceUsers.extraGroups = [ "docker" ];
  };

}
