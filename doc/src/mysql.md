(nixos-mysql)=

# MySQL

This component sets up a managed instance of the MySQL database server.

We use the [Percona Distribution for MySQL](https://percona.com/software/mysql-database)
which provides useful improvements over the standard Oracle MySQL/MariaDB implementations.

(nixos-mysql-versions)=

## Supported versions

There's a role for each supported major version, currently:

- mysql57: Percona 5.7.x (End-of-life)
- percona80: Percona 8.0.x (*LTS* release)
- percona83: Percona 8.3.x (*Innovation* release, End-of-life)
- percona84: Percona 8.4.x (*LTS* release)

Percona and MySQL currently follow a [two-fold release model](https://www.percona.com/blog/lts-and-innovation-releases-for-percona-server-for-mysql/)
and provide support for 2 releases in parallel:

- *LTS (recommended)*: These long-term support releases are supported throughout the full release life-time
  of this NixOS platform release and only receive minor bug and security fixes.
- *Innovation*: A new innovation release is made roughly each quarter of a year,
  containing new features and potentially breaking changes.\
  Please note that these releases won't receive any further upstream support once the successor
  is out. Our platform will keep each Innovation release made during the release life-time
  available, enabling you to update at your own pace. But we won't backport changes from
  newer Percona Innovation releases.

## Configuration

MySQL works out-of-the box without configuration.

You can change the password for the mysql *root* user in {file}`/etc/local/mysql/mysql.passwd`.
The MySQL service must be restarted to pick up the new password:

```
sudo systemctl restart mysql
```

Custom config files in {file}`/etc/local/mysql` are included in the
main mysql configuration file on the next system build.
Add a {file}`local.cnf` (or any other `*.cnf`) file there, and run
{command}`sudo fc-manage --build` to activate the new configuration.

:::{note}
Changes to \*.cnf files in this directory will restart MySQL
to activate the new configuration.
:::

## Interaction

You can find the password for the MySQL *root* user in {file}`/etc/local/mysql.passwd`.
Service users can read the password file.

Service users can use {command}`sudo -iu mysql` to access the
MySQL *root* account to perform administrative commands
and log files in {file}`/var/log/mysql`.
To connect to the local MySQL server, run {command}`mysql` as *mysql* user:

```
sudo -u mysql mysql
```

The MySQL server can be accessed from other machines in the same project on the
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

The default monitoring setup checks that the MySQL server process is
running and that it responds to connection attempts to the standard MySQL
port.

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
