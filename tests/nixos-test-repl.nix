# A simple helper to make it easier to interactively explore systems built by
# NixOS tests. Based on nixos-repl.nix, also see the top comment in that script.
# First, run it:
#
# nix repl -f nixos-test-repl.nix
#
# In the shell, load the test file that you want to explore:
# :l nginx.nix
#
# Test changes, nixpkgs changes and the REPL script itself can be reloaded from
# inside the REPL with the `:r` command.
# Tests can have multiple test cases and multiple machines so a bit more
# typing is needed compared to nixos-repl.nix
# For a typical test with one top-level test case and one VM called `machine`,
# config can be accessed at `driver.nodes.machine.config`.
# For example, to get the host name:
# print driver.nodes.machine.config.networking.hostName
# When multiple test cases are defined, you have to add the name of the test case:
# print testCase1.driver.nodes.server1.config.networking.hostName
# To show the final nginx config file content:
# etc driver.nodes.server1 "nginx/nginx.conf"

with builtins;
let
  pkgs = import <nixpkgs> {};

  etc = node: printEtcFile node;
  replHelpers = pkgs.callPackage ../nixos/lib/repl-helpers.nix {};
  inherit (replHelpers) printEtcFile format print;

in builtins // {
  inherit pkgs etc format print;
  inherit (pkgs) lib;
}
