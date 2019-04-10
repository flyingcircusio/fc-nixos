#!/bin/sh
# run bundler (creates Gemfile.lock) and bundix (creates gemset.nix)
set -x
rm -rf .bundle
rm -f Gemfile.lock
rm -rf /tmp/bundix
nix-shell -p git -p stdenv -p cacert -p bundler -p openssl -p nix-prefetch-scripts \
    --command "bundler package --all --no-install --path /tmp/bundix/bundle"
nix-shell -p bundix -p nix-prefetch-scripts --command bundix
