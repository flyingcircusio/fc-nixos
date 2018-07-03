# Pinned import
#
# Usage example:
#   nix-build -o nixpkgs ./nixpkgs.nix
#   export NIX_PATH=nixpkgs=$PWD/nixpkgs
{ nixpkgs ? import <nixpkgs> {}
, channelExtras ? {}  # extra paths for channel compilation
}:

let
  bootstrap = nixpkgs;

  version = "2f06e04";
  nixpkgsPatched = bootstrap.fetchurl {
    name = "nixpkgs-${version}.tar.gz";
    url = "https://github.com/flyingcircusio/nixpkgs-channels/archive/${version}.tar.gz";
    # update with `nix-prefetch-url $url`
    sha256 = "10vzjry6x8ray4h6q9r2g6a0nx0jpkac6w5qcv72qsz1bmn0ngb8";
  };

in

with bootstrap;

let
  copyExtras = builtins.concatStringsSep "\n"
    (lib.mapAttrsToList (tgt: src: "cp -r ${src} $out/${tgt}") channelExtras);

in stdenv.mkDerivation {
  name = "fc-nixpkgs";
  phases = [ "unpackPhase" "installPhase" ];
  src = nixpkgsPatched;
  installPhase = ''
    mkdir $out
    mv * .version $out
    ${copyExtras}
  '';
}
