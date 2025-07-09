{
  fetchFromGitHub,
  poetry2nix,
  lzo,
  python312,
  mkShellNoCC,
  poetry,
  runCommand,
  fetchPypi,

}@inputs:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "1286f7092334c7f0b846425e16304b0afd89d25d";
    hash = "sha256-ZCQTrLYoiTrt+sZdjnvdWjl2Y+ZAREDRDjaFDeUsd6U=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
