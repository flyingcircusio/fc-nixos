{
  fetchFromGitHub,
  callPackage,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "474d97c6826f1aa26a6457d465f6c35675590850";
    hash = "sha256-DHW0sLqRudMLItrBK/gl3pOTsR/MTFTL+niodFhQK2k=";
  };

  lib = callPackage "${src}/lib.nix" { inherit uv2nix pyproject-nix pyproject-build-systems; };

in
lib.packages.default
