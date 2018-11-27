{ config, pkgs, ... }:

with builtins;

{
  imports = (import ../module-list.nix);

  users.mutableUsers = false;

  environment = {
    systemPackages = with pkgs; [
      fc-userscan
      vim
    ];
    etc = {
      "nixos/configuration.nix".text = readFile ../etc_nixos_configuration.nix;
    };
  };

  nixpkgs.overlays = [ (import ../../pkgs/overlay.nix) ];
}
