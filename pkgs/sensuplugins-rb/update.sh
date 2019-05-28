#!/bin/sh
# Run this from a directory with a Gemfile to generate files needed by bundix there.
#
# Runs bundler (creates Gemfile.lock) and bundix (creates gemset.nix)
# Works for initial creation and later updates.
#
# Example: 
# cd sensu-plugins-postgres
# ../update.sh

set -x
set -e
rm -f Gemfile.lock
rm -rf /tmp/bundix
nix-shell --pure -p git stdenv cacert bundler openssl \
    --command "bundler package --all --no-install --path /tmp/bundix/bundle"
nix-shell --pure -p bundix nix-prefetch-scripts --command bundix
rm -rf .bundle
