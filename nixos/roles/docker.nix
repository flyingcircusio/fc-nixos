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

    networking.firewall.extraCommands = ''
      # allow access to host from docker networks, we consider this identical
      # to access from locally running processes.
      # We grant the full RFC1918 172.16.0.0/12 range.
      iptables -A nixos-fw -i br-+ -s 172.16.0.0/12 -j nixos-fw-accept
      iptables -A nixos-fw -i docker+ -s 172.16.0.0/12 -j nixos-fw-accept
    '';

  };

}
