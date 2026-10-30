#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash nixfmt

set -euo pipefail

EXTERNAL_DEPS=(
    "audit-userspace"
    "benchmark"
    "bzip2"
    "cJSON"
    "cpp-httplib"
    "curl"
    "dbus"
    "flatbuffers"
    "googletest"
    "jemalloc"
    "libarchive"
    "libbpf-bootstrap"
    "libdb"
    "libffi"
    "libpcre2"
    "libplist"
    "libyaml"
    "lua"
    "lzma"
    "msgpack"
    "nlohmann"
    "openssl"
    "pacman"
    "popt"
    "procps"
    "rocksdb"
    "rpm"
    "sqlite"
    "zlib"
)

# Single source of truth: passthru.dependencyVersion in ../default.nix.
# To bump it, follow README.md section "Choosing DEPENDENCY_VERSION".
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
DEPENDENCY_VERSION=$(sed -n 's/^[[:space:]]*dependencyVersion = "\([0-9]\+\)";.*/\1/p' "$SCRIPT_DIR/../default.nix")
[ -n "$DEPENDENCY_VERSION" ] || {
    echo "error: could not extract dependencyVersion from $SCRIPT_DIR/../default.nix" >&2
    exit 1
}
BASE_URL="https://packages.wazuh.com/deps/$DEPENDENCY_VERSION/libraries/sources"

# The generated file is a plain data list; default.nix maps entries to
# fetchurl calls. Keep this shape — list literals do not apply functions,
# so pre-applied fetchers inside the list would break evaluation.
# Written to a temp file and moved into place so a failed run never
# leaves a truncated external-dependencies.nix behind.
OUT=$(mktemp -p . --suffix .nix tmp-external-dependencies-XXXXXXXX)
trap 'rm -f "$OUT"' EXIT

echo "[" >> "$OUT"

for dep in "${EXTERNAL_DEPS[@]}"; do
    HASH=$(
        nix-prefetch-url "$BASE_URL/$dep.tar.gz" --type sha256 |
            xargs nix hash convert --from nix32 --to sri --hash-algo sha256 --extra-experimental-features nix-command
    )
    [ -n "$HASH" ] || {
        echo "error: prefetch or hash conversion failed for $dep" >&2
        exit 1
    }
    cat <<EOF >> "$OUT"
  {
    name = "$dep";
    hash = "$HASH";
  }
EOF
done

echo "]" >> "$OUT"

nixfmt "$OUT"
mv "$OUT" external-dependencies.nix
