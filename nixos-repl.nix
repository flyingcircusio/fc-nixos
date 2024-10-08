# A simple helper to make it easier to interactively explore the NixOS system.
# You have to run it as root because normal users are not allowed
# to evaluate the system, yet:
# sudo nix repl nixos-repl.nix
# System config, nixpkgs changes and the script itself can be reloaded from
# inside the repl with the `:r` command.
# `print` is a wrapper around builtins.trace that tries to
# pretty-print various types of Nix values. It outputs a hash of the
# printed string representation to be able to quickly spot if the output has
# changed between runs.
#
# Config attributes are at the top-level, so you can, for example,
# show effective postgresql settings with:
#   print services.postgresql.settings
# There's also the options attrset which you can use to find the files
# where an option is defined:
#   print options.services.postgresql.settings.files

with builtins;
let
  pkgs = import <nixpkgs> {};
  nixos = import <nixpkgs/nixos> {};
  inherit (nixos) options;

  etc = printEtcFile options;
  replHelpers = pkgs.callPackage nixos/lib/repl-helpers.nix {};
  inherit (replHelpers) printEtcFile format print;

in builtins // nixos.config // {
  inherit pkgs etc format print;
  inherit (pkgs) lib;
  inherit (nixos) config options;
}
