#!/usr/bin/env bash

nix flake update nixpkgs
nix run .#buildVersionsJson
nix run .#buildPackageVersionsJson
