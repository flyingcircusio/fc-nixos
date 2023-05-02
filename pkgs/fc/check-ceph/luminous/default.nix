{ pkgs, libyaml, python3Packages, ceph }:

let
  py = python3Packages;

in
  py.buildPythonApplication rec {
    name = "fc-check-ceph-luminous-${version}";
    version = "1.0";
    src = ./.;
    dontStrip = true;
    propagatedBuildInputs = [
      py.nagiosplugin
      ceph
    ];
  }
