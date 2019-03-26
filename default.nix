# nixpkgs with our overlay packages.
# This file gets referenced when you import <fc>.
# Set up environment: eval $(./dev-setup)
# Build upstream pacakge: nix-build -A hello
# Build own package: nix-build -A fc.userscan
# ===
# <nixpkgs> should usually point to FC patched upstream nixpkgs
{ nixpkgs ? <nixpkgs>
, localSystem ? builtins.intersectAttrs { system = null; platform = null; } args
, system ? localSystem.system
, platform ? localSystem.platform
, crossSystem ? null
, overlays ? []
, config ? {}
} @ args:

import nixpkgs {
  overlays = overlays ++ [ (import ./pkgs/overlay.nix) ];
} // args
