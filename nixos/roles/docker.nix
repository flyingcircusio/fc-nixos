{ config, lib, pkgs, ... }:
{
  options = {
    flyingcircus.roles.docker = {
      enable = lib.mkEnableOption "Enable Docker";
    };
  };

  config = lib.mkIf config.flyingcircus.roles.docker.enable {
    environment.systemPackages = [ pkgs.docker-compose ];
    # Policy routing interferes with host-container networking, disable it.
    flyingcircus.network.policyRouting.enable = false;
    flyingcircus.users.serviceUsers.extraGroups = [ "docker" ];
    virtualisation.docker.enable = true;
  };

}
