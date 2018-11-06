# nixpkgs with our overlay packages.
# Upstream pacakge: `nix-build default.nix -A hello`
# Own package: `nix-build default.nix -A fc-userscan`
# ===
# <nixpkgs> should usually point to FC patched upstream nixpkgs
{ nixpkgs ? <nixpkgs>
, localSystem ? builtins.intersectAttrs { system = null; platform = null; } args
, system ? localSystem.system
, platform ? localSystem.platform
, crossSystem ? null
, overlays ? []
} @ args:

import nixpkgs {
  overlays = overlays ++ [ (import ./pkgs/overlay.nix) ];
} // args
