(nixos-postgresql-server)=

# PostgreSQL

Managed instance of the [PostgreSQL](http://postgresql.org) database server.

## Components

- PostgreSQL server (versions 10, 11, 12, 13, 14)

## Configuration

Managed PostgreSQL instances already have a production-grade configuration with
reasonable sized memory parameters (for example, `shared_buffers`, `work_mem`).

:::{warning}
Putting custom configuration in {file}`/etc/local/postgresql/{VERSION}/*.conf`
doesn't work properly starting with NixOS 20.09 and should not be used anymore.
Some options from there will be ignored silently if they are already defined
by our platform code. Use NixOS-based custom config as described below instead.
:::

You can override platform and PostgreSQL defaults by using the
{code}`services.postgresql.settings` option in a custom NixOS module.
Place it in {file}`/etc/local/nixos/postgresql.nix`, for example:

```nix
{ config, pkgs, lib, ... }:
{
  services.postgresql.settings = {
      log_connections = true;
      huge_pages = "try";
      max_connections = lib.mkForce 1000;
  }
}
```

To override platform defaults, use {code}`lib.mkForce` before the wanted value
to give it the highest priority.

String values will automatically be enclosed in single quotes.
Single quotes will be escaped with two single quotes.
Booleans in Nix (true/false) are converted to on/off in the PostgreSQL config.

Run {command}`sudo fc-manage -b` to activate the changes (**restarts PostgreSQL!**).

See {ref}`nixos-custom-modules` for general information about writing NixOS
modules.

## Interaction

Service users can use {command}`sudo -u postgres -i` to access the
PostgreSQL super user account to perform administrative commands like
{command}`createdb` and {command}`createuser`.

Service users may invoke {command}`sudo fc-manage --build`
to apply configuration changes and restart the PostgreSQL
server (if necessary).

## Monitoring

The default monitoring setup checks that the PostgreSQL server process is
running and that it responds to connection attempts to the standard PostgreSQL
port.

## Platform-created Databases

We create the `nagios` database for monitoring purposes and `root` for the
root user. In a fresh installation, the following databases are present:
`nagios`, `postgres`, `root`, `template0`, `template1`

## Major Version Upgrades

Upgrading to a new major version, for example from 13.x to 14.x, requires a
migration of the old database cluster living in {file}`/srv/postgresql/13` to
the new data directory at {file}`/srv/postgresql/14`. A common way to do this
is to use {command}`pg_upgrade` bundled with PostgreSQL. This works on our
platform but doing it properly is not trivial.

To make it easy and to prevent common errors, we provide a `fc-postgresql`
command which prepares and runs upgrade migrations. It can also show the
current state of data directories for the available major versions.

:::{note}
{command}`fc-postgresql` has to be run as `postgres` user. Prefix the
commands with `sudo -u postgres` or use `sudo -iu postgres` to change
to the `postgres` user. This is allowed for `service` and `sudo-srv`
users.
:::

To show which data directories exists, their migration status and which
service version is running, use {command}`sudo -u postgres fc-postgresql list-versions`.
Add `--help` to see details about the meaning of the columns.

:::{note}
Please look at the output of {command}`sudo -u postgres fc-postgresql list-versions`
before performing an upgrade and make sure that your assumptions about
the current state (which version is active, which data dirs are there, ...)
are correct.
:::

The upgrade commands need to know which databases are expected to be present
in the cluster. Default databases created by PostgreSQL or our platform code
are always accepted and don't have to be specified.

If you have two databases, `mydb` and `otherdb`, for example, specify both on
the command line.

To prepare an upgrade, when you use the `postgresql13` role at the moment and
you want to change to `postgresql14`, run::

    sudo -u postgres fc-postgresql upgrade --new-version 14 --expected mydb --expected otherdb

Note that this is done while the old role is still active. It's safe to run
the command while PostgreSQL is running as it does not have an impact on the
current cluster and downtime is not required.

The command should automatically find the old data directory for 13, set up
the new data directory and succeed if no problems with the old cluster were
found. Problems may occur if the old cluster has been created with
non-standard settings which are not compatible with the new cluster, the old
directory has an invalid structure or multiple old data directories which
need migration are found.

:::{warning}
Depending on the machine and the amount of data, the next step may take
some time. PostgreSQL will not be available during the upgrade!
:::

To actually run the upgrade, use::

    sudo -u postgres fc-postgresql upgrade --new-version 14 --expected mydb --expected otherdb --upgrade-now

This will stop the postgresql service, prevent it from starting during the
upgrade, migrate data and mark the old data directory as migrated. This data
directory cannot be used by the postgresql service anymore after this point.

Run {command}`sudo -u postgres fc-postgresql list-versions` to see how the
status of the old and new data dir has changed.

After the migration, postgresql is still stopped and you have to change your
configuration to the new major version, for example by disabling the
`postgresql13` role and activating the `postgresql14` role, in one step.

If you really need to go back to the old version, delete the new data directory
as `postgres` user, remove the {file}`fcio_migrated_to*` files in the old data
directory and switch back to the old postgresql role.

## Miscellaneous

- Our PostgreSQL installations have the autoexplain feature enabled by default.

% vim: set spell spelllang=en:
