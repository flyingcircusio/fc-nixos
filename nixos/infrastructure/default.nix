{ config, lib, ... }:

{

  imports = [
    ./testing.nix
    ./flyingcircus.nix
    ./virtualbox.nix
    ./vagrant.nix
  ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = types.enum [ "testing" "flyingcircus" "virtualbox" "vagrant" ];
      default = "testing";
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
  };

}
