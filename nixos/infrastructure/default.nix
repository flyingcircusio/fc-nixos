{ config, lib, ... }:

{

  imports = [
    ./container.nix
    ./dev-vm.nix
    ./testing.nix
    ./flyingcircus-physical.nix
    ./flyingcircus-virtual.nix
    ./virtualbox.nix
  ];

  options = with lib; {
    flyingcircus.infrastructureModule = mkOption {
      type = types.enum [ "testing" "flyingcircus" "flyingcircus-physical" "virtualbox" "container" "dev-vm" ];
      default = "testing";
      example = "flyingcircus";
      description = "Load config module for specific infrastructure.";
    };
    flyingcircus.infrastructure.preferNoneSchedulerOnSsd = mkOption {
      type = types.bool;
      default = false;
      description = "If running on SSD set I/O scheduler to none";
    };
  };

}
