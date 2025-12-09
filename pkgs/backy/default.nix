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
    rev = "11a2b2695cccf6dc81b93c521fee410a0d971f6f";
    hash = "sha256-KDpqvehr76Luto7Fp2NhoXcIKmeSoSOpZqAhEu+8jEw=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
