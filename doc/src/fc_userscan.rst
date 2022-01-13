.. _nixos-fc_userscan:

fc-userscan
===========

Protects installed packages that might still be needed from grabage collection.

Rationale
---------

As in every other linux distribution, you may install some arbitrary library, manually compile a programm
against it and as long as this library exists, there is no problem. But NixOS some what amplities this by
the fact that even smallest changes somewhere down the dependency chain will change checksums from which
NixOS store paths are constructed. The garbage collection will remove the old version and break the programm.

`fc-userscan <https://github.com/flyingcircusio/userscan>`_ searches for references to nix store paths in
the service-user's directory and ensures that this packages are not garbage collected.

Exclusion
~~~~~~~~~

Indiscriminately blocking all packages that where refered to somewhere brings a new problem.
For example a logfile may refere to an old and unneeded nix package and as long as this log exists
the old package would not be deleted and the nix store grows in size. This is why fc-userscan excludes
some files from being scanned by default. If you need to add more exclusion rules you may add them as one regex per
line to `~/.userscan-ignore`. The home folder in this case is the home folder of the service user.
