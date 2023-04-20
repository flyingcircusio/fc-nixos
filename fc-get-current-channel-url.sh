#!/usr/bin/env bash

set -euo pipefail

branch=$1
nixos_version=$(< nixos-version)
jobset="fc-$nixos_version-$branch"

curl --silent --head https://hydra.flyingcircus.io/channel/custom/flyingcircus/${jobset}/release/nixexprs.tar.xz | grep "[Ll]ocation" | cut -f 2 -d " "
