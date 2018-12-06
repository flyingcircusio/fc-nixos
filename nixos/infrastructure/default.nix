{ config, lib, ... }:

with builtins;

let
  defaultInfrastructureModule =
    if pathExists /etc/nixos/vagrant.nix
    then "vagrant"
    else if pathExists /etc/nixos/virtualbox.nix
    then "virtualbox"
    else "flyingcircus";

in {

  imports = [ ./flyingcircus ./virtualbox ./vagrant ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = types.enum [ "flyingcircus" "virtualbox" "vagrant" ];
      default = defaultInfrastructureModule;
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
  };

}
