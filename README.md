Flying Circus NixOS Platform
============================

Development Mode
----------------

Run in the source tree:

    nix develop --impure

This enters the dev shell where NIX_PATH is set properly and various scripts are available.

Look at `flake.nix` to see how the dev shell is defined. The comment at the
top shows which commands are available in the dev shell.

Running a Test VM on a local dev checkout
-----------------------------------------

To use a local dev checkout on a FCIO test VM, sync the `fc-nixos` source tree to the target
machine:

    rsync -aP ~/git/fc-nixos example01:

On the machine, enter the dev shell and set up the `channels` directory:

    cd fc-nixos
    nix develop --impure
    build_channels_dir

This can be done as regular user. Exit the shell and run the commands again
when nixpkgs changes.

The VM has to use a matching environment that points to the `channels` dir.
`sudo fc-manage switch` then uses the local code to rebuild the system.


Automatically enter the dev shell with direnv
---------------------------------------------

Use `direnv` to automatically enter the dev shell when you change to the fc-nixos directory.

A recommended direnv config is shipped in `.envrc.example` to use it in your repo checkout just
`cp .envrc{.example,} && direnv allow`.

We recommend the usage of the [nix-community/nix-direnv](https://github.com/nix-community/nix-direnv) hook
instead of the one shipped by direnv itself.
To set it up with `home-manager`, see:
https://github.com/nix-community/nix-direnv?tab=readme-ov-file#via-home-manager

### Without home-manager

On a NixOS machine, enabling `programs.direnv.enable` should be enough.

Add `/etc/local/nixos/dev_vm.nix`, for example:

    { ... }:
    {
      nix.extraOptions = ''
        keep-outputs = true
      '';
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    }

Rebuild the system, close the shell/tmux session and log in again.

Run `direnv allow` again if the dev shell disappears or doesn't reload automatically.


Build Single Packages
---------------------

Run in development mode:

    nix-build -A $package

Or build package by directly calling a Nix expression:

    nix-build -E 'with import <fc> {}; callPackage path/to/file.nix {}'

Editable development versions of our core packages
--------------------------------------------------

fc.agent

    $ cd fc-nixos
    $ eval $(./dev-setup)  # not nix-shell!
    $ nix-shell pkgs/fc/agent
    $ which fc-manage
    /tmp/.../bin/fc-manage

fc.qemu

    TBD

(Dry-)Build System
------------------

Run in development mode:

    sudo nix-build '<nixpkgs/nixos>' -A system

(Must be executed as *root* on FCIO test VMs).


Execute Tests
-------------

Build a single test file and run the test script:

    nix-build tests/nginx.nix

Start the the interactive test runner:

    nix-build tests/nginx.nix -A driverInteractive
    result/bin/nixos-test-driver --interactive

Inside this Python REPL, you can

* Run separate commands and print their result with `print(machine.succeed("pwd"))`.
* Run the whole test script with `test_script()`.
* Interact with a test VM using `machine.shell_interact()`.

See the [NixOS Tests](https://nixos.org/manual/nixos/stable/index.html#sec-nixos-tests)
chapter of the NixOS manual for more details.

For test files with multiple test cases add the attribute name of the case, for example `nonprod` here:

    nix-build tests/fcagent.nix -A nonprod.driverInteractive


Some tests have arguments with a default value, often a `version` which can be overridden with `--argstr`:

    nix-build tests/postgresql.nix --argstr version 14 -A driverInteractive


Different versions of a test are exposed via separate attributes, you can also invoke them like this:

    nix-build release -A tests.postgresql14

Run the whole test suite (may take a very long time):

    nix-build release -A tested


Documentation
-------------

The platform documentation lives in `doc/src/` and is built with Zensical.
No Nix environment is needed to work on it: the `doc/appenv` wrapper manages
the Python environment via `uv`.

Start the live-reloading preview at http://localhost:8000:

    cd doc
    ./appenv python -m zensical serve -f zensical.toml

Or build the static HTML into `doc/_build/en/`:

    ./appenv python -m zensical build -f zensical.toml

The documentation is versioned: `doc/src/` always matches the OS code of the
current branch; snapshots of other versions are placed under `doc/src/<ver>/`
from local hg revisions, driven by `doc/platform-versions.toml`
(see `doc/README.md`).

See `doc/README.md` for details.


Update Pinned Dependencies
--------------------------

The nixpkgs and nixos-mailserver versions used by the platform are pinned in `flake.lock`. The versions and hashes are written to `release/versions.json` by our release tooling and read from there by platform code.

We use our [nixpkgs fork](https://github.com/flyingcircusio/nixpkgs) and the nixos-mailserver fork from our Gitlab.

Our nixpkgs fork is automatically updated by the update-nixpkgs GitHub action in fc-nixos-release-tools.

If you need to manually cherry-pick a commit from nixpkgs or add another commit on top of our nixpkgs fork, please add
the commit to the nixos-xx.xx (replace with the current version) and run

    ./update-nixpkgs-lock.sh

on an x86_64-linux machine and commit the changed files to this repository.

To learn more about our release tooling, look at the fc-nixos-release-tooling repo.

License
-------

Unless explicitly stated otherwise, content in this repository is licensed under the [MIT License](COPYING).
