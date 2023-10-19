let
  pkgs = import <fc> {};
  fcagent = pkgs.python310Packages.callPackage ./. {};
in
(fcagent.override { enableSlurm = true; }).overridePythonAttrs(_: {
  doCheck = true;
})
