# Wazuh Agent Package

Decision log for build patches and dependency handling. Each entry records what changed, why, and the upstream source where relevant.

For the NixOS module, see `nixos/services/wazuh/agent.nix`.

## Build Targets

Only the **agent** target is supported. Manager (server/local/hybrid) is out of scope.

```sh
make TARGET=agent
```

## Common Build Errors

If a build fails, check the errors below. These crop up when dependencies change or versions shift.

### Choosing `DEPENDENCY_VERSION`

`dependencyVersion` in `agent/default.nix` (passthru) is the single source of truth — the prefetch script reads it from there. When bumping the Wazuh version, re-derive it from the pinned upstream tag:

1. Open `src/Makefile` at the pinned tag and search for the `packages.wazuh.com/deps/<version>/libraries` download URLs — the version number in those URLs is the new `DEPENDENCY_VERSION`.
2. Set `dependencyVersion` in `agent/default.nix`.
3. Run the script and commit the regenerated `agent/dependencies/external-dependencies.nix`.

### External-dependencies failure

If you see something like:

```sh
curl -so external/cpython.tar.gz https://packages.wazuh.com/deps/51/libraries/linux/amd64/cpython.tar.gz || true
cd external && [ -f cpython.tar.gz ] && gunzip cpython.tar.gz || true
test -e external/cpython.tar || \
(curl -so external/cpython.tar.gz https://packages.wazuh.com/deps/51/libraries/sources/cpython_x86_64.tar.gz && \
cd external && gunzip cpython.tar.gz && tar -xf cpython.tar && rm cpython.tar)
make: *** [Makefile:<line>: external/cpython.tar.gz] Error 6
make: Leaving directory '/build/src'
```

The build tries to download dependencies at build time. In the Nix sandbox there's no network access, so `curl` fails — but the Makefile continues anyway due to `|| true`. We prefetch dependencies with `fetchurl` and place them where Wazuh expects them, so the failed download doesn't matter.

The failing target lives in the `external/*.tar.gz` download rules in `src/Makefile` — search for it there; the exact line number shifts between releases.

This error indicates either a missing dependency or an incorrect name. With `cpython` specifically, the source tarball has a `_x86_64` suffix but the Makefile expects `cpython.tar.gz`. Fix this by adding a rename step in `default.nix` using a `let in` expression with `fetchurl`.

For a missing dependency, add its name under `{url}` in `prefetch-external-dependencies.sh` and run the script.

### libbpf-bootstrap tarball changes

Upstream may change the tarball structure on `packages.wazuh.com` (member paths, `./` prefixes). The `postUnpack` extraction uses `--strip-components=2` accordingly — check the hash and internal structure in `dependencies/external-dependencies.nix` if this step breaks after a dependency bump.

## Patches

Each patch carries its what+why in its `#`-comment header.

Derivation-side adjustments live in `agent/default.nix` instead of patch
files: `substituteInPlace` in `prePatch`/`postPatch` (install user/group,
clang/bpftool paths, eBPF `CMAKE_C_FLAGS`, `modern.bpf.c` download
suppression) and `env.NIX_CFLAGS_COMPILE` (libdb warning downgrades).
