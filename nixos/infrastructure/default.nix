{ config, lib, ... }:

{

  imports = [
    ./flyingcircus.nix
    ./virtualbox.nix
    ./vagrant.nix
  ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = with types; nullOr (enum [ "flyingcircus" "virtualbox" "vagrant" ]);
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
  };

}
