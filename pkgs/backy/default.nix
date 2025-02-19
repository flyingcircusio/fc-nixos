{
  fetchFromGitHub,
  fetchPypi,
  poetry2nix,
  lzo,
  python310,
  mkShellNoCC,
  poetry,
  runCommand,
}@inputs:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "2.5.2";
    hash = "sha256-Tp6mQ9a/PBocw9unGexLvz55nMX+mnUUiUC6ZCCZ+8w=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
