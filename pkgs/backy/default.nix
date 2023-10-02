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
    rev = "e37a7f6570b6b9194cb3a27d8db2951eb5c992ce";
    hash = "sha256-s7FazUx/o68VY0gaSfzSMQI4XX8o1qqKf6IEoynM4nQ=";
  };

  lib = import "${src}/lib.nix" inputs;

in
lib.packages.default
