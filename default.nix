# Patched nixpkgs with our overlay packages.
# Upstream pacakge: `nix-build default.nix -A hello`
# Own package: `nix-build default.nix -A fc-userscan`
{ system ? builtins.currentSystem } @ args:

import (import ./nixpkgs.nix {}) {
  overlays = [ (import ./fc/pkgs/overlay.nix) ];
} // args
