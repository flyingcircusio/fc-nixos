# Wazuh Agent Package

See `../README.md` for patch explanations, build troubleshooting, and the
decision log. Build flow and patch details are derivable from `default.nix`.

## Key Files

- `default.nix` — Main derivation. stdenv.mkDerivation from GitHub source, prefetched external deps, custom install
- `dependencies/external-dependencies.nix` — 29 prefetched tarballs with SRI hashes
- `dependencies/prefetch-external-dependencies.sh` — Regenerates the .nix file from packages.wazuh.com (dep version 51)

## Conventions

- Patches apply to `src/` subdir within extracted `wazuh-X.Y.Z/src/`
- New deps: add name to `prefetch-external-dependencies.sh`, run it, commit updated `external-dependencies.nix`
- Multi-file patches combined into single `.patch` files
- External deps base URL: `https://packages.wazuh.com/deps/$DEPENDENCY_VERSION/libraries/sources`
- Dep version 51 for Wazuh 4.14.5
