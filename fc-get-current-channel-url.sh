#!/usr/bin/env bash

curl --silent --head https://hydra.flyingcircus.io/channel/custom/flyingcircus/fc-19.03-$1/release/nixexprs.tar.xz | grep Location | cut -f 2 -d " "
