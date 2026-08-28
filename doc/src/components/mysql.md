# MySQL { #nixos-mysql }

This component sets up a managed instance of the MySQL database server.

We use the [Percona Distribution for MySQL](https://percona.com/software/mysql-database)
which provides useful improvements over the standard Oracle MySQL/MariaDB implementations.

## Supported versions { #nixos-mysql-versions }

There's a role for each supported version, currently:

- percona84: Percona 8.4.x (*LTS* release)

Percona 9.7 will be the next version added as soon as it's released.

## Upgrade { #nixos-mysql-upgrade }

Upgrading to a newer version of MySQL happens in place.
The requirement for an in-place upgrade is to go from one LTS release to the next one, without skipping any.
This means e.g. upgrading 8.0 -> 8.4 -> 9.7.
Read the [MySQL](https://dev.mysql.com/doc/refman/8.4/en/upgrade-paths.html) documentation for more information.

## Configuration

MySQL works out-of-the box without configuration.

The root user is authenticated by socket auth with the `mysql` and `root` system users.

Custom config files in `/etc/local/mysql` are included in the
main mysql configuration file on the next system build.
Add a `local.cnf` (or any other `*.cnf`) file there, and run
`sudo fc-manage switch` to activate the new configuration.

!!! note
    Changes to \*.cnf files in this directory will restart MySQL
    to activate the new configuration.

## Interaction

Service users can use `sudo -iu mysql` to access the
MySQL *root* account to perform administrative commands
and log files in `/var/log/mysql`.
To connect to the local MySQL server, run `mysql` as *mysql* user:

```
sudo -u mysql mysql
```

The MySQL server can be accessed from other machines in the same resource group on the
default port 3306.

## Slow Log

SQL statements that take longer than 100 milliseconds to run, are logged to
`/var/log/mysql/mysql.slow`.
The log file is rotated when file size is greater than 2GB or at least weekly.

The default of 100 milliseconds for slow queries can be changed with a global
option: `SET GLOBAL long_query_time=1.5;` where the value is the time in seconds.

## Backup

For backup tasks the `xtrabackup` command is provided, along with sudo
permission for executing xtrabackup from the service user as root.

## Monitoring

The default monitoring setup checks that the MySQL server process is
running and that it responds to connection attempts to the standard MySQL
port.

## Populating with Initial Data

For populating the database with data or executing other custom SQL commands at
first startup, the NixOS option `services.percona.initialScript` can be set to a
file containing such SQL commands.

!!! caution
    This is mainly useful for [nixos-devhost](../components/devhost.md#nixos-devhost) deployments, as the script will only
    be executed at first startup and is ignored afterwards.

    Enabling a Percona role first and only setting an initial script later won't have
    any effect anymore.
    % hidden note as of 20240711: It is possible to re-trigger db initialisation by `touch /run/mysql_init`, but we have decided not to expose this as an official stable API.

## Migrate user password hash algorithm { #nixos-mysql-password-hash-migration }

Before Percona 8.4, we used `mysql_native_password` was the default authentication and password hash algorithm.
With 8.4 `caching_sha2_password` is the new default algorithm for new users.
Percona 9.7 will remove the `mysql_native_password` hash algorithm, so user password hashes need to be migrated before updating to Percona 9.7.

To get a list of users needing to be migrated, run the following SQL statement:

```sql
SELECT user,host,plugin FROM mysql.user WHERE plugin='mysql_native_password';
```

These users need to be manually migrated to the new algorithm with the following SQL statement (insert `username`, `host`, `password`):
```sql
ALTER USER 'username'@'host' IDENTIFIED WITH 'caching_sha2_password' by 'password';
```

Please check your MySQL client library support for `caching_sha2_password` before migrating the user.
