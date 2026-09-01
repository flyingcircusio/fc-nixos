# Flying Circus Platform Documentation

This directory contains the documentation for the Flying Circus platform,
built with [Zensical](https://github.com/flyingcircusio/zensical).

The documentation lives directly inside the `fc-nixos` monorepo: `doc/src/`
always matches the OS code of the current branch.

## How to Build and Preview Locally

We use `uv` (via the `appenv` wrapper) to manage dependencies and the Python
environment. You do not need a full Nix environment to build the docs!

1. **Start the local preview server:**
   ```bash
   ./appenv python -m zensical serve -f zensical.toml
   ```
   This will start a local web server at `http://localhost:8000`. It features
   live-reloading: any changes you make to the `.md` files in `src/` will
   instantly appear in your browser.

2. **Build everything (switcher payload, snapshots, HTML):**
   ```bash
   make
   ```
   or run the individual targets:

   | Target | What it does |
   | --- | --- |
   | `make gen-platform-versions` | Regenerates `src/_static/platform-versions.js` from `platform-versions.toml` and the page inventory |
   | `make checkout-versioned-docs` | Places version snapshots under `src/<ver>/` from local hg revisions |
   | `make html` | Builds the static HTML into `_build/en/` |

## Documentation Versioning

Versions are driven by `platform-versions.toml`: a `[current]` entry (the
local `doc/src/` tree -- never checked out), `[[prerelease]]` and
`[[sunsetting]]` entries, each naming a version and an **hg bookmark**.

- `tools/checkout_versioned_docs.py` resolves bookmarks **strictly locally**
  (no pull, no network) and exports snapshots under `src/<ver>/`.
- `[[prerelease]]` revisions are exported from their whole `doc/src/**` tree
  (the dev-branch shape).
- `[[sunsetting]]` revisions must carry their docs namespaced at
  `doc/src/<ver>/**` -- created by the branch's one-time **sunset move
  commit** (`hg mv doc/src doc/src/<ver>`). A sunsetting revision without
  that directory fails the build loudly with the remediation hint; there is
  deliberately **no fallback** to the whole-tree shape for old versions.
- Sunsetting pages receive `search: exclude` frontmatter and a warning banner
  linking to the current counterpart when it exists in the local tree.

## Version Switcher

The `src/_static/platform-versions.js` payload is **generated** by
`make gen-platform-versions` -- never edit it by hand. Releases and sunsets
are configured exclusively in `platform-versions.toml`. Which page carries a
version switcher in which versions is derived from the page inventory: a
page present in at least two trees is versioned and gets a switcher entry; a
page present in only one tree is a common page without its own switcher.

## Cross-Version Documents

Global texts (security policies, support guidelines) live in the current
tree. Older snapshots keep their own copies for contextual integrity; their
banner links readers to the current counterpart. Keeping global texts
current across snapshots is backport discipline on the version branches.
