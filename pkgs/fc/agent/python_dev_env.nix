#!/usr/bin/env -S nix-build -o pyenv
# Builds a Python environment for IDE integration (tested with Pycharm).
# Run this file with ./python_dev_env.nix.
# This creates a directory 'pyenv' which should be picked up py IDE as a possible
# project interpreter.

let
  pkgs = import <nixpkgs> {};
  fcagent = pkgs.callPackage ./. {};

in fcagent.pythonDevEnv
