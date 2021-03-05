{ config, lib, ... }:

{

  imports = [
    ./testing.nix
    ./flyingcircus-physical.nix
    ./flyingcircus-virtual.nix
    ./virtualbox.nix
    ./vagrant.nix
  ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = types.enum [ "testing" "flyingcircus" "flyingcircus-physical" "virtualbox" "vagrant" ];
      default = "testing";
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
  };

}
