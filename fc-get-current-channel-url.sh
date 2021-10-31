#!/usr/bin/env bash

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <release> <channel>" >&2
  exit 2
fi

RELEASE="$1"
CHANNEL="$2"

curl --silent --head https://hydra.flyingcircus.io/channel/custom/flyingcircus/fc-$RELEASE-$CHANNEL/release/nixexprs.tar.xz | grep "[Ll]ocation" | cut -f 2 -d " "
