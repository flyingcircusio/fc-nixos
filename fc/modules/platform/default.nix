{ config, pkgs, ... }:

with builtins;

{
  users.mutableUsers = false;
  users.users.root.password = "root";

  environment = {
    systemPackages = with pkgs; [
      hello
      fc-userscan
    ];
    etc = {
      "nixos/configuration.nix".text = readFile ../../configuration.nix;
    };
  };

  nixpkgs.overlays = [ (import ../../pkgs/overlay.nix) ];

}
