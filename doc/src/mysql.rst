.. _nixos-mysql:

MySQL
=====

Managed instance of the MySQL database server.

There's a role for each supported major version, currently:

* mysql56: Percona 5.6.
* mysql57: Percona 5.7.
* mysql80: Percona 8.0.

`Percona <https://percona.com/software/mysql-database>`_ is used instead of the more common MariaDB implementation.

This implementation is feature-compatible with regular Oracle/MariaDB installations
and provides useful improvements over the Oracle/MariaDB implementations.

Configuration
-------------

MySQL works out-of-the box without configuration.

Interaction
-----------

Service users can use :command:`sudo -u mysql -i` to access the
MySQL super user account to perform administrative commands
and access log files such as the slowlog.

Both service users and the `mysql` DB super user may invoke :command:`sudo
fc-manage --build` to apply configuration changes and restart the MySQL
server (if necessary).

For backup tasks the :command:`xtrabackup` command is provided, along with sudo
permission for executing xtrabackup from the serivce user as root.

Monitoring
----------

The default monitoring setup checks that the MySQL server process is
running and that it responds to connection attempts to the standard MySQL
port.
