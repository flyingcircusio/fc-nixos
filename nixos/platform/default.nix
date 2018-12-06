{ config, pkgs, lib, ... }:

with builtins;

{
  imports = (import ../module-list.nix);

  config = {
    environment = {
      etc."nixos/configuration.nix".text =
        readFile ../etc_nixos_configuration.nix;
    };

    nixpkgs.overlays = [ (import ../../pkgs/overlay.nix) ];

    system.stateVersion = mkDefault "18.09";
  };
}
