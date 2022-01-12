Flying Circus NixOS Platform
============================
a

Development Mode
----------------

Run in the source tree:

    eval $(./dev-setup)

This sets up the `channels` directory and NIX_PATH.

Development on a Test VM
------------------------

For development on a FCIO test VM, sync the fc-nixos source tree to the target
machine and set up the `channels` directory:

    ./dev-setup

This can be done as regular user.

The VM has to use a matching environment that points to the `channels` dir.
`fc-manage -b` (as root) then uses the local code to rebuild the system.

Development With Vagrant
------------------------

Changes to the platform code can be tested on a Vagrant VM.
There's a `Vagrantfile` and `vagrant-provision.nix` in the root directory of the repository.
Run `vagrant up` to start the VM and use `vagrant ssh` to connect to it.

Become root and prepare the environment:

    sudo -i
    cd /vagrant
    eval $(./dev-setup)

To rebuild the system on the Vagrant VM with your changes, use:

    nixos-rebuild test

`fc-manage` would rebuild with the original dev channel, so we are using `nixos-rebuild` here.

Build packages
--------------

Run in development mode:

    nix-build -A $package

Or build package by directly calling a Nix expression:

    nix-build -E 'with import <nixpkgs> {}; callPackage path/to/file.nix {}'


(Dry) system build
------------------

Run in development mode:

    nix-build '<nixpkgs/nixos>' -A system


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
