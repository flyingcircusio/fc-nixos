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

To set it up with `home-manager`, see:
https://github.com/nix-community/nix-direnv?tab=readme-ov-file#via-home-manager

Without home-manager
--------------------

On a NixOS machine, enabling `programs.direnv.enable` should be enough.

Add `/etc/local/nixos/dev_vm.nix`, for example:

    { ... }:
    {
      nix.extraOptions = ''
        keep-outputs = true
      '';
      programs.direnv.enable = true;
    }

Rebuild the system, close the shell/tmux session and log in again.

In `fc-nixos`, add an `.envrc` file like:

    use flake . --impure --allow-dirty
    build_channels_dir

Then, run `direnv allow` to build and enter the dev shell.

Run `direnv allow` again if the dev shell disappears or doesn't reload automatically.


Build Single Packages
---------------------

Run in development mode:

    nix-build -A $package

Or build package by directly calling a Nix expression:

    nix-build -E 'with import <fc> {}; callPackage path/to/file.nix {}'


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


Update Pinned Dependencies
--------------------------

The nixpkgs and nixos-mailserver versions used by the platform are pinned in `flake.lock`. The versions and hashes are written to `release/versions.json` by our release tooling and read from there by platform code.

We use our [nixpkgs fork](https://github.com/flyingcircusio/nixpkgs) and the nixos-mailserver fork from our Gitlab.

The typical workflow for a nixpkgs update looks like this (run in the dev shell):

1. Rebase local nixpkgs onto current upstream version: `update_nixpkgs --nixpkgs-path ~/worksets/nixpkgs/fc/nixos-23.11 nixpkgs`
2. Update `versions.json` and `package-versions.json` (must be able to talk to hydra01): `update_nixpkgs fc-nixos`
3. Create a draft PR with the changes and wait until Hydra finishes building.
4. When Hydra is green, try it out on a test VM. Don't forget to run `build_channels_dir` if you haven't set up direnv!

To learn more about our release tooling, look at the comment in `flake.nix` at the top.

License
-------

Unless explicitly stated otherwise, content in this repository is licensed under the [MIT License](COPYING).
