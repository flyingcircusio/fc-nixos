{
  fetchFromGitHub,
  lib,
  stdenv,
  poetry2nix,
  lzo,
  python312,
  mkShellNoCC,
  poetry,
  runCommand,
  libiconv,
  darwin,
  rustPlatform,

}@inputs:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    # FIXME: currently targets a PR branch PL-133651
    rev = "9fa1a828495e14d3eb65000935022aef8083db9a";
    hash = "sha256-ssU4sUtD8SliP/ZcqGwXkSZ0xPpSdiCx3R3rAROwb3k=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
