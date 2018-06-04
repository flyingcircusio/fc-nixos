# Usage example: `nix-build release.nix -A nixos.channel`
{ nixpkgs ? import ./nixpkgs.nix, ...  } @ args :
import "${nixpkgs}/nixos/release-small.nix" args
