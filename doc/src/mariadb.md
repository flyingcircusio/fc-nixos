(nixos-mariadb)=

# MariaDB

This component sets up a managed instance of the MariaDB database server.

(nixos-mariadb-versions)=

## Supported versions

There's a role for each supported version, currently:

- mariadb114: MariaDB 11.4 (LTS)
- mariadb118: MariaDB 11.8 (LTS)

We recommend the use of `mariadb118`, as this is the most up to date LTS release.
All of versions marked with EOL don't receive security updates and are only included to allow
the upgrade of existing machines to this platform version.

## Configuration

MariaDB works out-of-the box without configuration.

The mysql user is authenticated by socket auth with the `mysql` system users.

Custom config files in {file}`/etc/local/mysql` are included in the
main mysql configuration file on the next system build.
Add a {file}`local.cnf` (or any other `*.cnf`) file there, and run
{command}`sudo fc-manage switch` to activate the new configuration.

:::{note}
Changes to \*.cnf files in this directory will restart MariaDB
to activate the new configuration.
:::

## Interaction

Service users can use {command}`sudo -iu mysql` to access the
MySQL *mysql* account to perform administrative commands
as well as log files in {file}`/var/log/mysql`.
To connect to the local MariaDB server, run {command}`mariadb` as *mysql* user:

```
sudo -u mysql mariadb
```

The MariaDB server can be accessed from other machines in the same resource group on the
default port 3306.

## Slow Log

SQL statements that take longer than 100 milliseconds to run, are logged to
{file}`/var/log/mysql/mysql.slow`.
The log file is rotated when file size is greater than 2GB or at least weekly.

The default of 100 milliseconds for slow queries can be changed with a global
option: `SET GLOBAL long_query_time=1.5;` where the value is the time in seconds.

## Backup

For backup tasks the {command}`xtrabackup` command is provided, along with sudo
permission for executing xtrabackup from the service user as root.

## Monitoring

The default monitoring setup checks that the MariaDB server process is
running and that it responds to connection attempts to the standard MariaDB
port (3306).

## Populating with Initial Data

For populating the database with data or executing other custom SQL commands at
first startup, the NixOS option `services.percona.initialScript` can be set to a
file containing such SQL commands.

:::{caution}
This is mainly useful for {ref}`nixos-devhost` deployments, as the script will only
be executed at first startup and is ignored afterwards.

Enabling a Percona role first and only setting an initial script later won't have
any effect anymore.
% hidden note as of 20240711: It is possible to re-trigger db initialisation by `touch /run/mysql_init`, but we have decided not to expose this as an official stable API.
:::
