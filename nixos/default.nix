{ config, pkgs, lib, ... }:

with builtins;

{
  imports = [
    ./lib
    ./infrastructure
    ./platform
    ./version.nix
  ];

  config = {
    environment = {
      etc."nixos/configuration.nix".text =
        import ./etc_nixos_configuration.nix { inherit config; };
    };

    nixpkgs.overlays = [ (import ../pkgs/overlay.nix) ];
  };
}
