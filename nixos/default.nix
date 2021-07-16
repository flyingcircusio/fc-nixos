{ config, pkgs, lib, ... }:

with builtins;

{
  imports = [
    ./infrastructure
    ./lib
    ./platform
    ./services
    ./version.nix
  ];

  config = {
    environment = {
      etc."nixos/configuration.nix".text =
        import ./etc_nixos_configuration.nix { inherit config; };

      etc._nix-phps.source = ../nix-phps;
    };

    nixpkgs.overlays = [ (import ../pkgs/overlay.nix) ];

  };
}
