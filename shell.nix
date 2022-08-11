{ pkgs ? import <nixpkgs> {} }:
with builtins;
let
  lib = pkgs.lib;
  channels = (import ./versions.nix { });
  nixPathUpstreams =
    lib.concatStringsSep
    ":"
    (lib.mapAttrsToList (name: channel: "${name}=${channel}") channels);

  nixosRepl = pkgs.writeShellScriptBin "nixos-repl" ''
    sudo -E nix repl nixos-repl.nix
  '';

in pkgs.mkShell {
  name = "fc-nixos";
  shellHook = ''
    export NIX_PATH="fc=${toString ./.}:${nixPathUpstreams}:nixos-config=/etc/nixos/configuration.nix"
    export PATH=$PATH:${nixosRepl}/bin
  '';
}
