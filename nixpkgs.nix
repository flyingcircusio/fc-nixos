{ pkgs ? import <nixpkgs> {}
}:

let
  versionInfo = pkgs.lib.importJSON ./version.json;

in pkgs.fetchFromGitHub rec {
  inherit (versionInfo) owner repo rev sha256;
  name = "nixpkgs-${rev}";
}
