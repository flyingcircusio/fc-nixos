{
  fetchFromGitHub,
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
    rev = "2.5.1";
    hash = "sha256-w83Q7d3vJmh5dLiL7iI7K8YbMvWKQtr9pTsL9u7jAEg=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
