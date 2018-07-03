#!/usr/bin/env bash
# Usage: export `./setup.sh`
base=$PWD
nixpkgsBootstrap=$(realpath $HOME/.nix-defexpr/channels_root/nixpkgs)
if [[ -z nixpkgsBootstrap ]]; then
    echo "$0: need <nixpkgs> available in system channels" >&2
    exit 1
fi
export NIX_PATH="nixpkgs=$nixpkgsBootstrap:fc-nixos=$base"
nixpkgs=`nix-build -Q -o nixpkgs $base/nixpkgs.nix`
if [[ -z $nixpkgs ]]; then
    echo "$0: failed to build nixpkgs+overlay" >&2
    exit 1
fi
echo "NIX_PATH=$NIX_PATH:nixos-config=$base/fc/configuration.nix:$base"
