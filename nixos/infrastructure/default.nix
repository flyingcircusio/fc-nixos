{ config, lib, ... }:

{

  imports = [ ./flyingcircus ./virtualbox ./vagrant ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = types.enum [ "flyingcircus" "virtualbox" "vagrant" ];
      default = "flyingcircus";
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
  };

}
