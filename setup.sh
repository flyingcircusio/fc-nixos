#!/usr/bin/env bash
# Usage: export `./setup.sh`
if [[ $0 =~ / ]]; then
    base=$(realpath ${0%%/*})
else
    base=$PWD
fi
nixpkgs=`nix-build -Q -o nixpkgs $base/nixpkgs.nix`
if [[ -z $nixpkgs ]]; then
    echo "$0: failed to build nixpkgs+overlay" >&2
    exit 1
fi
echo "NIX_PATH=nixos-config=$base/fc/configuration.nix:$base:$base/nixpkgs"
