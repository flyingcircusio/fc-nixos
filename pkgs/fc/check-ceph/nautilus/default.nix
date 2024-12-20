{ pkgs, libyaml, python3Packages, ceph-client, libceph }:

let
  py = python3Packages;

in
  py.buildPythonApplication rec {
    name = "fc-check-ceph-nautilus-${version}";
    version = "1.0";
    src = ./.;
    dontStrip = true;
    propagatedBuildInputs = [
      py.nagiosplugin
      (py.toPythonModule ceph-client)
      py.toml
    ];
    checkInputs = [
      py.pytest
    ];

    checkPhase = ''
      pytest .
    '';
  }
