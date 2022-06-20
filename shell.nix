{ pkgs ? import <nixpkgs> {} }:
with builtins;
let
  lib = pkgs.lib;
  channels = (import ./versions.nix { });
  nixPathUpstreams =
    lib.concatStringsSep
    ":"
    (lib.mapAttrsToList (name: channel: "${name}=${channel}") channels);

  nixosRepl = pkgs.writeShellScriptBin "nixos-repl" "nix repl nixos-repl.nix";

in pkgs.mkShell {
  name = "fc-nixos";
  NIX_PATH="fc=${toString ./.}:${nixPathUpstreams}:nixos-config=/etc/nixos/configuration.nix";
  shellHook = ''
    export PATH=$PATH:${nixosRepl}/bin
  '';
}
