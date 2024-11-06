#!/usr/bin/env bash

set -e

base="./changelog.d"
branch=$(git rev-parse --abbrev-ref HEAD)

new_item="${base}/$(date '+%Y%m%d_%H%M%S')_${branch/\//\-}_scriv.md"
cp "${base}/new_fragment.md.j2" ${new_item}
$EDITOR $new_item
