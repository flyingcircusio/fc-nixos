let
  pkgs = import <nixpkgs> {};
  versions = import ../../../versions.nix { inherit pkgs; };
  nixos-23_05 = import versions.nixpkgs-23_05 {};
  fcagent = nixos-23_05.python310Packages.callPackage ./. {};
in
fcagent.overridePythonAttrs(_: {
  doCheck = true;
})
