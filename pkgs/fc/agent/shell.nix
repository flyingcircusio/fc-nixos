let
  pkgs = import <fc> { };
  fcagent = pkgs.python312Packages.callPackage ./. { };
in
(fcagent.override { enableSlurm = false; }).overridePythonAttrs (_: {
  doCheck = true;
})
