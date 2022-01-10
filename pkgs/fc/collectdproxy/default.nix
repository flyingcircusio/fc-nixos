{ pkgs
, python3Packages
}:

let
  py = python3Packages;

in
py.buildPythonPackage rec {
  name = "collectdproxy-${version}";
  version = "1.0";
  namePrefix = "";
  dontStrip = true;
  src = ./.;
  doCheck = false;

  buildInputs = [
    py.pytest
  ];
}
