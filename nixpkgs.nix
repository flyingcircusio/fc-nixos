# Pinned import
#
# Usage example:
#   nix-build -o nixpkgs ./nixpkgs.nix
#   export NIX_PATH=nixpkgs=$PWD/nixpkgs
with builtins;

let
  version = "8aa3850";

  nixpkgsSrc = builtins.fetchTarball {
    name = "nixpkgs-${version}.tar.gz";
    url = "https://github.com/NixOS/nixpkgs-channels/archive/${version}.tar.gz";
    # update with `nix-prefetch-url --unpack $url`
    sha256 = "1jvii5zr7prp65kw3lm0yyzf9iwj9ikcf8npiw6vg4ws1m3i972a";
  };

  nixpkgs' = import nixpkgsSrc { };

in

nixpkgs'.stdenv.mkDerivation {
  name = "fc.nixpkgs";
  phases = [ "unpackPhase" "patchPhase" "installPhase" ];
  src = nixpkgsSrc;
  patches = [
    ./patches/issue.patch
  ];
  installPhase = ''
    cp -a . $out
  '';
}
