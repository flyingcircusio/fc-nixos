.. _nixos-mysql:

MySQL
=====

This component sets up a managed instance of the MySQL database server.

There's a role for each supported major version, currently:

* mysql56: Percona 5.6.
* mysql57: Percona 5.7.
* mysql80: Percona 8.0.

MySQL 5.6 / Percona 5.6 is end-of-life and should be upgraded.


We use the `Percona Distribution for MySQL <https://percona.com/software/mysql-database>`_
which provides useful improvements over the standard Oracle MySQL/MariaDB implementations.

Configuration
-------------

MySQL works out-of-the box without configuration.

You can change the password for the mysql root user in :file:`/etc/local/mysql/mysql.passwd`.
The MySQL service must be restarted to pick up the new password::

    sudo systemctl restart mysql


Custom config files in :file:`/etc/local/mysql` are included in the
main mysql configuration file on the next system build.
Add a :file:`local.cnf` (or any other `*.cnf`) file there, and run
:command:`sudo fc-manage --build` to activate the new configuration.

.. note::

    Changes to \*.cnf files in this directory will restart MySQL
    to activate the new configuration.

Interaction
-----------

You can find the password for the MySQL root user in :file:`/etc/local/mysql.passwd`.
Service users can read the password file.

Service users can use :command:`sudo -iu mysql` to access the
MySQL super user account to perform administrative commands
and log files in :file:`/var/log/mysql`.
To connect to the local MySQL server, run :command:`mysql` as *mysql* user::

    sudo -u mysql mysql


The MySQL server can be accessed from other machines in the same project on the
default port 3306.

Slow Log
--------

SQL statements that take longer than 100 milliseconds to run, are logged to
:file:`/var/log/mysql/mysql.slow`.
The log file is rotated when file size is greater than 2GB or at least weekly.

The default of 100 milliseconds for slow queries can be changed with a global
option: ``SET GLOBAL long_query_time=1.5;`` where the value is the time in seconds.

Backup
------

For backup tasks the :command:`xtrabackup` command is provided, along with sudo
permission for executing xtrabackup from the service user as root.

Monitoring
----------

The default monitoring setup checks that the MySQL server process is
running and that it responds to connection attempts to the standard MySQL
port.
