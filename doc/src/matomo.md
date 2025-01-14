(nixos-matomo)=

# Matomo

Managed instance of [Matomo](https://matomo.org), a real-time Web analytics application. By default, we use the the latest LTS version provided by NixOS which is 5.x.x.

Matomo 4.x.x is not supported anymore by this platform version, please ensure that you have upgraded from that version.

(nixos-matomo-upgrade)=

## Upgrading to Matomo 5

The upgrade from Matomo 4 to 5 contains breaking changes especially
relevant when using additional plugins. Ensure that your plugins are
compatible to Matomo 5 before upgrading.

The 24.11 platform already sets `matomo_5` as the default package to be used. Hence, when upgrading from platform 24.05 with matomo-4, the upgrade will happen automatically.
:::{warning}
Before upgrading, test Matomo 5 on a separate staging instance, if possible. Migrating from Matomo 4 to 5 is irreversible without manual admin intervention!
:::


It is also possible to upgrade to matomo_5 while still using the 24.05 platform:

To use Matomo 5, set the `services.matomo.package` option manually in custom config, like this:

(note the added `pkgs` argument at the top of the module)

```nix
# /etc/local/nixos/matomo.nix
# XXX: Example config for Matomo 5
{ config, lib, pkgs, ... }:
{
  flyingcircus.roles.matomo = {
    hostname = "matomo.test.example.org";
  };

  services.matomo.package = pkgs.matomo_5;
}
```

The database and other Matomo state will be migrated automatically on service start after switching the system to the new config.


## Initial Setup

The `matomo` role sets up the Matomo PHP application and Nginx as reverse proxy
with an automatically managed Letsencrypt certificate.

:::{note}
Matomo requires manual setup: you need to set the host name, create a database
and run the Web installer.
:::

Matomo requires a MySQL-compatible database which is
not activated automatically. You can put the database on the same machine or
use a separate one. We recommend the {ref}`percona80 <nixos-mysql>` role for
the database.


### Add Matomo NixOS config

Before activating the `matomo` role, add at least the following custom config:

```nix
# /etc/local/nixos/matomo.nix
# XXX: Example config for Matomo 4
{ config, lib, ... }:
{
  flyingcircus.roles.matomo = {
    hostname = "matomo.test.example.org";
  };
}
```
See {ref}`nixos-custom-modules` for general information about writing custom NixOS
modules in {file}`/etc/local/nixos`.

### Create the database

Assuming that `percona80` is running on the same machine, create a database with
full privileges for the local matomo user. Matomo will create the necessary
database objects during the Web installer process.

```sh
sudo -u mysql mysql
```

```sql
create user matomo@localhost;
create database matomo;
grant all on matomo.* to matomo@localhost;
```

### Run the Web installer


Go to the configured URL, for example `https://matomo.test.example.org` and
start the Web installer.

On the third step which sets up the database, use `localhost` as "Database
Server" and `matomo` for both "Login" and "Database Name". Keep "Password"
empty and remove the default "Table Prefix". "Adapter" should be
`PDO\MySQL`.

After clicking "Next", Matomo confirms that tables have been created.

Finish the following steps and log in with your admin credentials.

### Geolocation

You probably want geolocation which requires an external database.
Set it up it via `Administration -> System -> Geolocation`.
Choose `DBIP / GeoIP 2` and Matomo will automatically download the database.

Also see
[Setting up accurate visitors geolocation](https://matomo.org/faq/how-to/setting-up-accurate-visitors-geolocation/)
in the Matomo FAQ.

### Archive Processing

The role automatically sets up the `matomo-archive-processing` service which
runs every hour. You can disable browser-triggered archiving, especially for
high-traffic websites:

Go to `Administration > System -> General Settings`, and select:

*Archive reports when viewed from the browser: No*

## Updates

:::{warning}
Please do not try to update Matomo manually, files will be overwritten!
:::

Updates are handled by the role. New versions overwrite files in the
installation directory, copied from the `matomo` Nix package. If needed,
database migrations are also run automatically.

## Interaction

As `sudo-srv` user, use matomo-console to run various Matomo management
commands:

```sh
sudo -u matomo matomo-console
```

## Configuration

### Plugins

As `sudo-srv` or `service` user, put plugin bundles in `/var/lib/matomo/plugins`.
Activate plugins with:

```sh
sudo -u matomo matomo-console plugin:activate ExamplePlugin
```

## NixOS Options

**services.matomo.periodicArchiveProcessing**

Archive processing is enabled by default.

**services.matomo.nginx.**

Put additional nginx virtual host settings here which are the same options as
`services.nginx.virtualHosts.<name>.*`, for example:

```nix
{
  services.matomo.nginx = {
    default = true;
    basicAuth = "FCIO login";
    basicAuthFile = "/etc/local/htpasswd_fcio_users";
  };
}
```

**services.matomo.package**

Package version to use. Default is `pkgs.matomo_5`.
`pkgs.matomo_beta` might be used as a newer but unsupported version.

## Monitoring

The role defines the following Sensu checks:

* `matomo-config`
* `matomo-permissions`
* `matomo-unexpected-files`
* `matomo-version`
