{ config, pkgs, lib, ... }:

let
  attrsets = import ./attrsets.nix { inherit config lib; };
  files = import ./files.nix { inherit config pkgs lib; };
  math = import ./math.nix { inherit pkgs lib; };
  network = import ./network.nix { inherit config pkgs lib; };
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
      { inherit attrsets files math network system utils; }
      // attrsets // files // math // network // system // utils;
  };
}
