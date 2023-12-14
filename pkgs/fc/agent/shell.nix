let
  pkgs = import <fc> {};
  fcagent = pkgs.python310Packages.callPackage ./. {};
in
(fcagent.override { enableSlurm = false; }).overridePythonAttrs(_: {
  doCheck = true;
})
