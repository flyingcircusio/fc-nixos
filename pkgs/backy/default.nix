{
  fetchFromGitHub,
  poetry2nix,
  lzo,
  python310,
  mkShellNoCC,
  poetry,
  runCommand,
  lib,
  stdenv,
  darwin,
  rustPlatform,
  libiconv,
}@inputs:
let
  src = fetchFromGitHub {
    owner = "flyingcircusio";
    repo = "backy";
    rev = "integrate-backy-extract";
    hash = "sha256-I8qcBzmKHHrowkcoLj92ocTAFMnJzqPHDl4TGbel9V4=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
