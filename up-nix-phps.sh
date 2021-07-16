#!/usr/bin/env nix-shell
#! nix-shell -i bash -p git curl jq

set -euo pipefail

T=$(mktemp -d)

trap "echo cleaning... && rm -rf '$T'" EXIT

pushd "$T"
git clone https://github.com/fossar/nix-phps "$T"
REV=$(cat flake.lock | jq -r .nodes.nixpkgs.locked.rev)
curl -L "https://github.com/nixos/nixpkgs/archive/$REV.tar.gz" | tar xz
popd

rm -rfv nix-phps
mkdir -p nix-phps/pkgs/development/interpreters nix-phps/pkgs/top-level nix-phps/pkgs/build-support
cp -vr "$T/pkgs" "$T/LICENSE.md" nix-phps
cp -vr $T/*/pkgs/development/interpreters/php nix-phps/pkgs/development/interpreters
cp -v $T/*/pkgs/top-level/php-packages.nix nix-phps/pkgs/top-level
cp -vr $T/*/pkgs/development/php-packages nix-phps/pkgs/development/php-packages
cp -v $T/*/pkgs/build-support/build-pecl.nix nix-phps/pkgs/build-support
echo -e "# imported\n\nThis is imported using up-nix-phps.sh from https://github.com/fossar/nix-phps\nRun ./up-nix-phps.sh to update" > nix-phps/README.md
