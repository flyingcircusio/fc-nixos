#!/usr/bin/env -S nix-build -o pyenv
# Used for IDE integration (tested with VSCode, Pycharm).
# Run this file with ./python_dev_env.nix.
# It creates a directory 'pyenv' that is similar to a Python virtualenv.
# The 'pyenv' should be picked up py IDE as a possible project interpreter (restart may be required).
{ pkgs ? import <nixpkgs> {} }:
let
 agent = pkgs.callPackage ./. {};

in pkgs.python3.withPackages (ps: [ agent ])
