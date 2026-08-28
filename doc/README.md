# Flying Circus Platform Documentation

This directory contains the documentation for the Flying Circus platform, built with [Zensical](https://github.com/flyingcircusio/zensical). 

Because the documentation now lives directly inside the `fc-nixos` monorepo, **the documentation is versioned via Git branches.** The documentation you see in the `src/` folder exactly matches the OS code of the current branch.

## How to Build and Preview Locally

We use `uv` (via the `appenv` wrapper) to manage dependencies and the Python environment. You do not need a full Nix environment to build the docs!

1. **Start the local preview server:**
   ```bash
   ./appenv python -m zensical serve -f zensical.toml
   ```
   This will start a local web server at `http://localhost:8000`. It features live-reloading: any changes you make to the `.md` files in `src/` will instantly appear in your browser.

2. **Build the static HTML (optional):**
   ```bash
   ./appenv python -m zensical build -f zensical.toml
   ```
   This generates the final HTML output in the `_build/en/` directory.

## Cross-Version Documentation (Global Docs)

Documents like Security Policies or Support Guidelines are "global" und should always show the latest version, even if a user is browsing the documentation for an older release (like `26.05`). 

**You do not need to do anything manually.** 
Our CI/CD pipeline handles this automatically: before building the documentation for an older branch, the pipeline runs `git checkout origin/master -- doc/src/security doc/src/support`. This physically pulls the latest global texts into the build context of the old branch, ensuring the user always reads the newest policies without any broken navigation links.

## Version Switcher

To allow users to switch between versions, the documentation relies on the `src/_static/platform-versions.js` file.
When releasing a new version or sunsetting an old one, simply update the JSON array in this file across the active branches. The UI will automatically render the dropdown and warning banners based on the `current` key.
