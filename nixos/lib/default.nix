{ config, pkgs, lib, ... }:

let
  files = import ./files.nix { inherit pkgs lib; };
  math = import ./math.nix { inherit pkgs lib; };
  network = import ./network.nix { inherit pkgs lib; };
  system = import ./system.nix { inherit config pkgs lib; };
  utils = import ./utils.nix { inherit config pkgs lib; };

in
{
  options = {
    fclib = lib.mkOption {
      default = {};
      type = lib.types.attrs;
      description = "FC-specific helper functions.";
    };
  };

  config = {
    fclib =
      { inherit files math network system utils; }
      // files // math // network // system // utils;
  };
}
