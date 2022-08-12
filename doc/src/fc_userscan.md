.. _nixos-fc_userscan:

fc-userscan
===========

Protects installed packages that might still be needed from garbage collection.

Rationale
---------

As in every other linux distribution, you may install some arbitrary library, manually compile a programm
against it and as long as this library exists, there is no problem. But NixOS some what amplifies this by
the fact that even smallest changes somewhere down the dependency chain will change hashes from which
NixOS store paths are constructed. The garbage collection will remove the old version if it's not referenced anymore.

`fc-userscan <https://github.com/flyingcircusio/userscan>`_ searches for references to nix store paths in
the users' home directories and ensures that these packages are not garbage collected.

Exclusion
~~~~~~~~~

Blocking all packages that are refered to somewhere brings a new problem.
For example a logfile may refer to an old and unneeded Nix package and as long as this log exists
the old package would not be deleted and the nix store grows in size. This is why fc-userscan excludes
some files from being scanned by default. If you need to add more exclusion rules you may add them as one regex per
line to `~/.userscan-ignore`. This uses the same pattern format as `gitignore <https://git-scm.com/docs/gitignore>`_. The home folder in this case is the home folder of the service user.
