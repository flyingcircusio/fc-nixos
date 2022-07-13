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

## Major Version Upgrades

Upgrading to a new major version, for example from 13.x to 14.x, requires a
migration of the old database cluster living in {file}`/srv/postgresql/13` to
the new data directory at {file}`/srv/postgresql/14`. A common way to do this
is to use {command}`pg_upgrade` bundled with PostgreSQL. This works on our
platform but finding the right arguments for the command is not trivial.

To make it easy, we have a `fc-postgresql` command which can show the
current state of data directories for the available major versions, prepare
and run upgrade migrations.

:::note
{command}`fc-postgresql` has to be run as `postgres` user. Prefix the
commands with `sudo -u postgres` or use `sudo -iu postgres` to change
to the `postgres` user. This is allowed for `service` and `sudo-srv`
users.
:::

To show which data directories exists, their migration status and which
service version is running, use {command}`fc-postgresql list-versions`.

:::note
Please look at the output of {command}`fc-postgresql list-versions`
before performing an upgrade and make sure that your assumptions about
the current state (which version is active, which data dirs are there, ...)
are correct.
:::

To prepare an upgrade, for example, when you use the `postgresql13` role at
the moment and you want to change to `postgresql14`, run
{command}`fc-postgresql upgrade --new-version 14` while the old role is
still active. It's safe to run the command while PostgreSQL is running as it
does not have an impact on the current cluster and downtime is not required.

The command should automatically find the old data directory for 13, set up
the new data directory and succeed if no problems with the old cluster were
found. Problems may occur if the old cluster has been created with
non-standard settings which are not compatible with the new cluster, the old
directory has an invalid structure or multiple old data directories which
need migration are found.

:::warning
Depending on the machine and the amount of data, the next step may take
some time. PostgreSQL will not be available during the upgrade!
:::

To actually run the upgrade, use {command}`fc-postgresql upgrade --new-version
14 --upgrade-now`. This will stop the postgresql service, migrate data and
mark the old data directory as migrated. It cannot be used by the postgresql
service anymore after this point.

Run {command}`fc-postgresql list-versions` to see how the status of the old
and new data dir has changed.

After the migration, postgresql is still stopped and you have to change your
configuration to the new major version, for example by disabling the
`postgresql13` role and activating the `postgresql14` role, in one step.

If you really need to go back to the old version, delete the new data directory
as `postgres` user, remove the {file}`fcio_migrated_to*` files in the old data
directory and switch back to the old postgresql role.


## Miscellaneous

Our PostgreSQL installations have the autoexplain feature enabled by default.

% vim: set spell spelllang=en:
