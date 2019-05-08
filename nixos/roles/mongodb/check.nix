{ pkgs ? import <nixpkgs> { }
, python27Packages ? pkgs.python27Packages
}:

let
  py = python27Packages;

in
  py.buildPythonPackage rec {
    name = "mongo-check-${version}";
    version = "1.0";
    namePrefix = "";
    src = ./.;
    dontStrip = true;
    propagatedBuildInputs = [ py.pymongo ];
  }
