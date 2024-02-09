#!/usr/bin/env bash
branch="${1:-production}"
nixos_version=$(< release/nixos-version)
jobset="fc-$nixos_version-$branch"

echo "Checking $jobset"

curl --silent --head "https://hydra.flyingcircus.io/channel/custom/flyingcircus/${jobset}/release/nixexprs.tar.xz" | grep "[Ll]ocation" | cut -f 2 -d " "
