.. _nixos-mysql:

MySQL
======

Managed instance of the `MySQL`_ database server.

There's a role for each supported major version, currently:

* mysql56: Percona 5.6.
* mysql57: Percona 5.7.
* mysql80: Percona 8.0.

Percona is used instead of the more common MariaDB implementation.

This implementation is feature-compatible with regular Oracle/MariaDB installations
and provides useful improvments over the Oracle/MariaDB implementations.

Configuration
-------------

MySQL works out-of-the box without configuration.

Interaction
--------

For backup tasks the `xtrabackup` command is provided, along with sudo access for it
