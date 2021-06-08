{ pkgs ? import <nixpkgs> {} }:
with builtins;
let
  lib = pkgs.lib;
  channels = (import ./versions.nix { });
  nixPathUpstreams =
    lib.concatStringsSep
    ":"
    (lib.mapAttrsToList (name: channel: "${name}=${channel}") channels);

in pkgs.mkShell {
  name = "fc-nixos";
  NIX_PATH="fc=${toString ./.}:${nixPathUpstreams}";
}
