{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
}:

let
  versions = pkgs.lib.importJSON ./versions.json;

  channels =
    lib.mapAttrs (
      name: repoInfo:
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

builtins.derivation {
  args = [ "-e" arrangeChannels ];
  builder = pkgs.stdenv.shell;
  channels = lib.mapAttrsToList (name: path: "${name} ${path}") channels;
  name = "channel-sources";
  PATH = with pkgs; lib.makeBinPath [ coreutils utillinux ];
  preferLocalBuild = true;
  system = builtins.currentSystem;
}
