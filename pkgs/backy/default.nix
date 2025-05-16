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
    # FIXME: currently targets a PR branch PL-133651
    rev = "64f0944a7747dd543534aa83a85813030b7fcf4d";
    hash = "sha256-oXntbqWkgMQZqdoFx1n4BoukFiqwnzJ0w8uQ0zU1FAw=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
