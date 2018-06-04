# Usage example: `nix-build default.nix -A hello`
{ system ? builtins.currentSystem } @ args:

import (import ./nixpkgs.nix) args
