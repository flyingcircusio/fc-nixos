(nixos-upgrade)=

# What's New & Upgrading

Here you find information about changes compared to the previous platform
version, what to consider and where to take action before upgrading.

:::{note}
Before upgrading a machine, please read the {ref}`nixos-upgrade-general`
and {ref}`nixos-upgrade-breaking`.
Contact our {ref}`support` for upgrade assistance.
:::

(nixos-upgrade-overview)=

## Overview for this version

- First production release: [2023_005 (2023-03-13)](https://doc.flyingcircus.io/platform/changes/2023/r005.html)
- Added roles: postgresql15
- Removed roles: {ref}`graylog, loghost, loghost-location <nixos-upgrade-loghost>`, {ref}`kibana, kibana6, kibana7 <nixos-upgrade-kibana>`, {ref}`postgresql10 <nixos-upgrade-postgresql>`
- Roles with significant breaking changes: {ref}`nginx, webgateway <nixos-upgrade-webgateway>`, {ref}`nixos-upgrade-statshost-master`


## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 22.11 ends on **2023-06-30**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.


## How to upgrade?

At the moment, upgrading for customers is only possible by setting the
platform version using the API or asking our {ref}`support` to schedule an
upgrade in a maintenance window or upgrade immediately.

We are working on a feature to request upgrades from the customer self-service
portal.

(nixos-upgrade-general)=

## General upgrade remarks

Our goal is to make upgrades as smooth as possible without manual intervention
but sometimes incompatible configuration has to be fixed before starting an
upgrade or behaviour changes of.

Here are some remarks to make sure that an upgrade will run successfully:

### Isolate application deployments

As a general advice: reduce platform dependencies of your application
deployment by using Nix-managed service user environments as described in
{ref}`nixos-user-package-management` or other forms of dependency isolation
like containers.

### Upgrade staging first

Upgrades should always be checked in a staging environment first. We usually
upgrade customer staging machines from our side as soon as the new platform
version is ready for general testing. This is announced via our
[Flying Circus Statuspage](https://status.flyingcircus.io) where you can
also subscribe to updates.

### Upgrade to the next platform version

We recommend upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 22.05 platform.

Direct upgrades from older versions are possible in principle, but we cannot
reliably test all combinations for all roles and custom configuration also
plays a role here. Usually, problems that occur when skipping versions are
only temporary, like service failures that go away with the next system
rebuild or a system/service restart.

### Check free disk space

About 8-10 GiB should be available on disk before starting an upgrade to avoid
triggering a low-disk alarm.

Usually, upgrades have an on-disk size of about 3-6 GiB which may be higher in
certain configurations. We keep old system versions and let the Nix garbage
collection clean them up, so the additional space will be used for at least 3
days.

### Consider performance impact while upgrading

Upgrading may take some time, depending on the number of activated roles and
disk speed. For production machines, upgrades are usually done in a
maintenance window to not affect regular operations too much. VM may have
degraded performance for some minutes when packages are being downloaded and
built.

With NixOS, the switch to the new system happens after a successful system
build so most services are unavailable at the same time and only for a small
time-window.

(nixos-upgrade-breaking)=

## Significant breaking changes

These changes often require action before the upgrade. Please review the
following common breaking changes and role-specific notes below.

### Common breaking changes

- Deprecated settings `logrotate.paths` and `logrotate.extraConfig` have been
  removed. Please convert any uses to `services.logrotate.settings` instead
  before upgrading.

(nixos-upgrade-webgateway)=

### webgateway

**Nginx** now uses the *nginx* user to run the main process.

This may cause problems when certificates are read from arbitrary directories,
for example deployments in `/srv/s-user`.

Normally, the built-in support for Letsencrypt should be used instead to avoid
permission problems and make sure that certificates are rotated
automatically.

If using external certificates cannot be avoided, make sure
that permissions allow read access for the *nginx* user, for example by
applying `setfacl -Rm u:nginx:rX` to the certificate directory.

It's also possible to keep the old behavior for some time by adding

```nix
# /etc/local/nixos/nginx-master-user-root.nix
{
  services.nginx.masterUser = "root";
}
```

as {ref}`nixos-custom-modules` before the upgrade. This setting will trigger a
deprecation warning on 23.05 and be removed in a later version.

(nixos-upgrade-statshost-master)=

### statshost-master

The options to add custom Grafana config have changed.

`services.grafana.extraOptions` has been removed and free-form config
settings moved to `services.grafana.settings`. For example,
`services.grafana.smtp.port` is now at `services.grafana.settings.smtp.port`.

For a detailed migration guide, please look at the
[NixOS 22.11 release notes](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-22.11-notable-changes).

### nginx

See {ref}`nixos-upgrade-webgateway`.

(nixos-upgrade-postgresql)=

### postgresql

The `postgresql10` role has been removed. {ref}`Upgrade the database <nixos-postgresql-major-upgrade>`
to a newer role version before the platform upgrade.

The `postgresql15` role is now available.

(nixos-upgrade-kibana)=

### kibana

All `kibana*` roles have been removed. Machines that use kibana should stay on
22.05 for now and move to OpenSearch/OpenSearch Dashboards later which we are
working on for 22.11.

(nixos-upgrade-loghost)=

### loghost

`graylog` and `loghost*` roles have been removed. Machines that use these
roles should stay on 22.05. We are working on a new logging stack for 22.11
which will be based on [Grafana Loki](https://grafana.com/oss/loki/).


## Other notable changes

- PHP is now built in NTS (Non-Thread Safe) mode by default. For Apache and
  mod_php usage, we enable ZTS (Zend Thread Safe) mode. This has been a
  common practice for a long time in other distributions.
- openssh was updated to version 9.1, disabling the generation of DSA keys
  when using `ssh-keygen -A` as they are insecure. Also, `SetEnv` directives
  in `ssh_config` and `sshd_config` are now first-match-wins.
- Python now defaults to 3.10, updated from 3.9. Python 3.11 is now stable.
- PHP now defaults to PHP 8.1, updated from 8.0.
- OpenSSL now defaults to OpenSSL 3, updated from 1.1.1.
- The `nodePackages` package set now defaults to the LTS release in the `nodejs`
  package again, instead of being pinned to `nodejs-14_x`. `nodejs-10_x` has
  been removed.
- For more details, see the
  [release notes of NixOS 22.11](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-22.11-notable-changes).


## Significant package updates

- docker-compose: 1.29 -> 2.12
- git: 2.36 -> 2.38
- gitlab: 15.4.6 -> 15.8.4
- glibc: 2.34 -> 2.35
- haproxy: 2.5 -> 2.6
- k3s: 1.23 -> 1.25
- keycloak: 18 -> 20
- nix: 2.8 -> 2.11
- openssh: 9.0 -> 9.1
- postfix: 3.6.6 -> 3.7.3
- powerdns: 4.6 -> 4.7
- rabbitmq: 3.9 -> 3.10
- roundcube: 1.5 -> 1.6
- systemd: 250 -> 251
- telegraf: 1.22 -> 1.24
- varnish: 7.1 -> 7.2
- zlib: 1.2.12 -> 1.2.13
- zsh: 5.8 -> 5.9
