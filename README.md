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

Execute test
------------

Automatic test execution for a single test:

    nix-build tests/$test.nix

Interactive test execution (gives a Perl REPL capable to run the test script):

    nix-build test/$test.nix -A driver
    ./result/bin/nixos-test-driver

For test files with sub tests use:

    nix-build test/$test.nix -A $subtest-attrname.driver


Update nixpkgs version
----------------------

1. Update rev id in versions.json and zero out sha256
2. Run `nix-build versions.nix` to get the correct checkout
3. Fix checksum and run `eval $(./dev-setup)` to activate.


License
-------

Unless explicitly stated otherwise, content in this repository is licensed under the [MIT License](COPYING).
