let
  pkgs = import <nixpkgs> {};
  fcagent = pkgs.python310Packages.callPackage ./. {};
in
fcagent.overridePythonAttrs(_: {
  doCheck = true;
})
