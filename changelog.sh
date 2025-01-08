#!/usr/bin/env bash

set -e

if [ -z "$EDITOR" ]; then
  echo "Error: \$EDITOR is not set or empty"
  exit 1
fi

base="./changelog.d"
branch=$(git rev-parse --abbrev-ref HEAD)

new_item="${base}/$(date '+%Y%m%d_%H%M%S')_${branch//\//-}_scriv.md"
template="${base}/new_fragment.md.j2"

cp "$template" "$new_item"

if ! $EDITOR "$new_item" || diff -q "$template" "$new_item" > /dev/null; then
  echo "Editor failed or content not changed. Deleting fragment..."
  rm "${new_item}"
fi
