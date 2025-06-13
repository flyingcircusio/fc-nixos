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
    rev = "2.5.3";
    hash = "sha256-EAD8VtoEUOoJpvajo8fFZcaxkTwDkWGsnckt9BDTkT0=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
