# Pinned import
#
# Usage example:
#   nix-build -o nixpkgs ./nixpkgs.nix
#   export NIX_PATH=nixpkgs=$PWD/nixpkgs

{ channelExtras ? {}  # extra paths for channel compilation
}:

let
  version = "94d80eb";

  nixpkgsOrig = fetchTarball {
    name = "nixpkgs-${version}.tar.gz";
    url = "https://github.com/flyingcircusio/nixpkgs-channels/archive/${version}.tar.gz";
    # update with `nix-prefetch-url --unpack $url`
    sha256 = "1l4hdxwcqv5izxcgv3v4njq99yai8v38wx7v02v5sd96g7jj2i8f";
  };

  nixpkgs' = import nixpkgsOrig { system = builtins.currentSystem; };

in

with nixpkgs';

let
  copyExtras = builtins.concatStringsSep "\n"
    (lib.mapAttrsToList (tgt: src: "cp -r ${src} $out/${tgt}") channelExtras);

in stdenv.mkDerivation {
  name = "fc.nixpkgs";
  phases = [ "unpackPhase" "installPhase" ];
  src = nixpkgsOrig;
  installPhase = ''
    mkdir $out
    mv * .version $out
    ${copyExtras}
  '';
}
