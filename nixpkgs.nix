{ pkgs ? import <nixpkgs> {} }:

with pkgs.lib;

let
  versions = importJSON ./versions.json;

  channels =
    mapAttrs (
      name: repoInfo:
      # Hydra expects fixed length rev ids
      assert builtins.stringLength repoInfo.rev == 40;
      pkgs.fetchFromGitHub {
        inherit (repoInfo) owner repo rev sha256;
        name = "${name}-${builtins.substring 0 7 repoInfo.rev}";
      })
      versions;

  arrangeChannels =
    builtins.toFile "arrange-channels.sh" ''
      mkdir $out
      set -- ''${channels[@]}
      # 1=name 2=path
      while [[ -n "$1" && -n "$2" ]]; do
        ln -s $2 $out/"$1"
        shift 2
      done
    '';

in
assert channels ? "nixpkgs";
# export "nixos-18_03" instead of "nixos-18.03" for example
(mapAttrs' (
  name: val:
  nameValuePair (replaceStrings [ "." ] [ "_" ] name) val) channels)
//
{
  allUpstreams = builtins.derivation {
    args = [ "-e" arrangeChannels ];
    builder = pkgs.stdenv.shell;
    channels = mapAttrsToList (name: path: "${name} ${path}") channels;
    name = "all-upstream-sources";
    PATH = with pkgs; makeBinPath [ coreutils ];
    preferLocalBuild = true;
    system = builtins.currentSystem;
  };
}
