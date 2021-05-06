#!/bin/sh
set -x
export NIX_PATH="nixpkgs=$(dirname $0)/../../../../../"
rm -rf .bundle
rm -f Gemfile.lock
rm -rf /tmp/bundix
nix-shell -p git -p stdenv -p stdenv -p cacert -p bundler -p openssl \
    -p nix-prefetch-scripts \
    --command "bundler package --all --no-install --path /tmp/bundix/bundle"
nix-shell -p bundix -p nix-prefetch-scripts --command bundix
