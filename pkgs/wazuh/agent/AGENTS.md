# Wazuh Agent Package

See `../README.md` for build troubleshooting and the decision log. Build flow
and patch details are derivable from `default.nix`.

## Key Files

- `default.nix` — main derivation
- `dependencies/external-dependencies.nix` — prefetched tarball hashes
- `dependencies/prefetch-external-dependencies.sh` — regenerates the .nix file

## Conventions

- Patch rationale lives in each patch's `#`-comment header, not in the README
- Prefer derivation-side adjustments (`substituteInPlace`, `env.NIX_CFLAGS_COMPILE`) over patch files when there is no structural change
- New deps: add the name to `prefetch-external-dependencies.sh`, run it, commit the regenerated `external-dependencies.nix`
