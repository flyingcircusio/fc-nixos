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
    rev = "1af98d7aaa3cf78dd20589633422455a533de182";
    hash = "sha256-NQuUWHnuJT5S/78alMO4EjZdz22FwGJHo4NxiZLEri4=";
  };

  lib = callPackage "${src}/lib.nix" { inherit uv2nix pyproject-nix pyproject-build-systems; };

in
lib.packages.default
