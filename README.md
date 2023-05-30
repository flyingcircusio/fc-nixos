Flying Circus NixOS Platform
============================

Development Mode
----------------

Run in the source tree:

    eval $(./dev-setup)

This sets up the `channels` directory and NIX_PATH.

Development on a Test VM
------------------------

For development on a FCIO test VM, sync the fc-nixos source tree to the target
machine and set up the `channels` directory with:

    ./dev-setup

This can be done as regular user. Run the command again when nixpkgs changes
in order to update the `channels` directory.

The VM has to use a matching environment that points to the `channels` dir.
`fc-manage switch` (as root) then uses the local code to rebuild the system.


Build Single Packages
---------------------

Run in development mode:

    nix-build -A $package

Or build package by directly calling a Nix expression:

    nix-build -E 'with import <nixpkgs> {}; callPackage path/to/file.nix {}'


(Dry-)Build System
------------------

Run in development mode:

    nix-build '<nixpkgs/nixos>' -A system

Must be executed as *root* on FCIO test VMs.


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


Update Pinned Nixpkgs
---------------------

We pin the used nixpkgs version in `versions.json` to a commit id from our
[nixpkgs fork](https://github.com/flyingcircusio/nixpkgs). The typical workflow
for a nixpkgs update looks like this:

1. Prefetch hash for new version: `nix-prefetch-github flyingcircusio nixpkgs --rev nixos-23.05`
2. Change rev and sha256 in `versions.json` according to the prefetch output.
3. Create a draft PR with the changed `versions.json` and wait until Hydra finishes building.
4. When Hydra is green, try it out on a test VM. Don't forget to run `./dev-setup`  to update the `channels` directory!


License
-------

Unless explicitly stated otherwise, content in this repository is licensed under the [MIT License](COPYING).
