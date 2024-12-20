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
    rev = "ecfb9849a6516d9fdbd0e0b97fd28216e13f4c91";
    hash = "sha256-ENtzVjNaouFHySOmQ3KLGQsBL+8YxtIm5PvLiEYq+5E=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
