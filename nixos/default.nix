{ config, pkgs, lib, ... }:

with builtins;

{
  imports = [
    ./infrastructure
    ./platform
  ];

  config = {
    environment = {
      etc."nixos/configuration.nix".text =
        readFile ./etc_nixos_configuration.nix;
    };

    nixpkgs.overlays = [ (import ../pkgs/overlay.nix) ];
  };
}
