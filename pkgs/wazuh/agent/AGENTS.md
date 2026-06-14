# Wazuh Agent Package

**Generated:** 2026-06-11

See `../README.md` for patch explanations and build troubleshooting.

## Key Files

- `default.nix` — Main derivation. stdenv.mkDerivation from GitHub source, prefetched external deps, custom install
- `dependencies/external-dependencies.nix` — 29 prefetched tarballs with SRI hashes
- `dependencies/prefetch-external-dependencies.sh` — Regenerates the .nix file from packages.wazuh.com (dep version 51)

## Patches

| Patch | Purpose |
|-------|---------|
| `01-makefile-patch.patch` | DB_LIB linkage, OpenSSL perl/Configure, Privsep_SetUser early return |
| `02-libbpf-bootstrap.patch` | Disable git/HTTP fetching (sandbox), suppress implicit-function-declaration |
| `03-cstdint-include.patch` | Missing `#include <cstdint>` in `sqlite_wrapper.h` |
| `04-snap-onerror-signature.patch` | GCC 15 lambda signature mismatch in `PostRequestParameters.onError` |

## Build Flow

1. `fetchFromGitHub` wazuh v4.14.5
2. `postUnpack` — external deps unpacked into `src/external/`
3. `dontConfigure = true` — no `./configure`
4. `preBuild` — `make deps` inside source tree
5. `installPhase` — `install.sh binary-install` into `$out`
6. `fixupPhase` — remove libgcc refs, add systemd to rpath for `wazuh-logcollector`

## Troubleshooting

- Build fails with `curl` errors in sandbox: Wazuh tries to download deps at build time. We prefetch them with `fetchurl`, so `curl` failures are expected/harmless. If a new dep is missing, add it to `prefetch-external-dependencies.sh`.
- `libbpf-bootstrap.tar.gz` changes: Upstream may change tarball structure on `packages.wazuh.com`. Check hash and internal structure if build breaks.

## Conventions

- Patches apply to `src/` subdir within extracted `wazuh-X.Y.Z/src/`
- New deps: add name to `prefetch-external-dependencies.sh`, run it, commit updated `external-dependencies.nix`
- Multi-file patches combined into single `.patch` files
- External deps base URL: `https://packages.wazuh.com/deps/$DEPENDENCY_VERSION/libraries/sources`
- Dep version 51 for Wazuh 4.14.5
