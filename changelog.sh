#!/usr/bin/env bash

set -e

base="./changelog.d"

new_item="${base}/$(date '+%Y%m%d_%H%M%S')_$(git rev-parse --abbrev-ref HEAD)_scriv.md"
cp "${base}/new_fragment.md.j2" ${new_item}
$EDITOR $new_item
