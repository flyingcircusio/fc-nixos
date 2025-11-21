(nixos-upgrade)=

# Platform Upgrades & What's New

Here you find information about changes compared to the previous platform
version, what to consider and where to take action before upgrading.

:::{note}
Before upgrading a machine, please read the {ref}`nixos-upgrade-general`
and {ref}`nixos-upgrade-breaking`.
Contact our [support](/platform/index.html#support) for upgrade assistance.
:::

(nixos-upgrade-overview)=

## Overview

- New roles:
    - {ref}`postgresql18 <nixos-upgrade-postgresql>`
- Removed roles:
    - {ref}`mysql57 <nixos-upgrade-percona>`
    - {ref}`percona83 <nixos-upgrade-percona>`
    - {ref}`postgresql13 <nixos-upgrade-postgresql>`
- Roles affected by significant breaking changes:
    - {ref}`webgateway <nixos-upgrade-webgateway>`
    - {ref}`mailserver <nixos-upgrade-mail>`
    - {ref}`slurm-controller slurm-node <nixos-upgrade-slurm>`
- Removed significant packages:
    - `gcc12`
    - `go_1_23`
    - `k3s_1_30`
    - `netstat`
    - `mongodb-6-0`
    - `percona-server_8_3`
    - `percona-xtrabackup_8_3`
    - `ruby_3_2`
    - `webkitgtk`

## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 25.05 ends on **2025-12-31**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.

## How to upgrade?

To upgrade your machines, the *Environment* to one of the `fc-25.11-…`
values. \
This can be done either via our customer portal, or by setting the platform
version using the API.

(nixos-upgrade-general)=

## General upgrade remarks

Our goal is to make upgrades as smooth as possible without manual intervention
but sometimes incompatible configuration has to be fixed before starting an
upgrade.

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

We strongly advise upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 24.11 platform.
Please refrain from opening support cases for broken upgrade paths from older
platform versions. The resolution is to upgrade one version at a time.

Direct upgrades from older versions are not tested since we cannot
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
maintenance window to reduce impact on regular operations. A VM may have
degraded performance for some minutes when packages are being downloaded and
built.

With NixOS, the switch to the new system happens after a successful system
build so most services are unavailable at the same time and only for a small
time-window.

(nixos-upgrade-breaking)=

## Significant breaking changes

(nixos-upgrade-webgateway)=

### Webgateway: nginx

In this release, we further do the migration from `flyingcircus.services.nginx`
to the upstream NixOS `services.nginx`.
For this release, we still provide the option `flyingcircus.services.virtualHosts`
with the same options available as with `services.nginx.virtualHosts` to provide you
with a simpler migration path.
This option will be removed, so please migrate to `services.nginx.virtualHosts` by then.

We have removed and changed a few custom options in this process:

- flyingcircus.services.nginx.disableDHEATMitigation: The DHEAT mitigation is now part of
  services.nginx.recommendedTlsSettings. Please override the nginx option `ssl_prefer_server_ciphers` manually if you
  explicitly want to disable this behavior.
- `flyingcircus.nginx.virtualHosts.<vhost>.listenAddress`: Use `services.nginx.virtualHosts.<vhost>.listenAddresses`
- `flyingcircus.nginx.virtualHosts.<vhost>.listenAddress6`: Use `services.nginx.virtualHosts.<vhost>.listenAddresses`
- `flyingcircus.nginx.virtualHosts.<vhost>.emailACME`: Use `security.acme.certs.<name>.email`
- `flyingcircus.nginx.virtualHosts.<vhost>.enableACME` is no longer implicitly enabled when `.onlySSL`, `.enableSSL`,
  `.addSSL` or `.forceSSL` is enabled.
  Please explicitly set `.enableACME = true` in that case

We expect the affected hosts to be minimal. We issue evaluation warnings in fc-nixos 25.05 for any of these cases.
If you are a guided or hosted customer, please check these warnings with `fc-manage check` on the VM with the
`webserver` role or contact our support.
If no warnings show up with this command, you are not affected by these changes.

We also adapted virtual hosts configured with `services.nginx.virtualHosts` to listen on the FE network interface per
default instead of on any interface.
This is also the behavior of `flyingcircus.services.nginx.virtualHosts` had in fc-nixos 25.05 and before.

(nixos-upgrade-percona)=

### Percona / MySQL

Two versions of percona are actively supported: `percona80` and `percona84`.
Both are LTS releases still receiving bug and security fixes.

`percona83` has been removed, as announced in the 25.05 release.
Please upgrade to `percona84` before upgrading.

`mysql57` has also been removed, as it's end-of-life for 2 years.
Please upgrade to `percona80` or `percona84` before upgrading.

(nixos-upgrade-postgresql)=

### PostgreSQL

PostgreSQL version 18 is available as a new `postgresql18` role.
There are no breaking changes in the integration of PostgreSQL into the Flying Circus platform, but the database
software itself includes some major changes
listed [in its Release Notes](https://www.postgresql.org/docs/release/18.0/).
Migrating between major versions of PostgreSQL requires migrating the data directory. See {ref}
`nixos-postgresql-major-upgrade` for how out platform can help with that.

`postgresql13` has been removed, as it's end-of-life. Please update to `postgresql14` or newer.

(nixos-upgrade-slurm)=

### Slurm

This release contains a major version upgrade of Slurm from 24.11.x.x (NixOS 25.05) to 25.05.x.x. Nodes of a cluster
need to be upgraded in a particular order, please consult the [upgrade instructions of the role](#nixos-slurm-upgrade)
for details.

Regarding new features or changes in Slurm itself,
consult [its release notes](https://github.com/SchedMD/slurm/blob/slurm-25-05-0-1/RELEASE_NOTES.md).

(nixos-upgrade-mail)=

### Mail server

IMAP over STARTTLS (port 143) and POP over STARTTLS (port 110) have been disabled as these ports are deprecated by
RFC8314 4.1.
Currently, you can still enable these ports with `mailserver.enableImap = true` and `mailserver.enablePop3 = true`
respectively.
These options will be removed with fc-nixos 26.05. Please migrate your client or application to IMAP or POP with TLS.

## Other notable changes

### Handling of out-of-memory situations (virtual machines only)

We have evolved the handling of situations where systems run out of memory. This
has resulted in a more proactive monitoring of memory conditions with the goal
to avoid kernel stalls and long periods of lockup on virtual machines.

`systemd-oomd` is now actively being used and configured to start killing (and
restarting) suspect services if a system starts using more than 50% of the
available swap. Our tests have shown that this results in faster automated
recoveries with only very short periods of downtime in cases of extreme and
sudden memory pressure. If this happens we receive automatic tickets to follow
up on this event during regular office hours.

Some low-level services (like `sshd`, `dbus` and a few others) are never swapped
and will never be killed by `systemd-oomd`.

### k3s-server

The internal PostgreSQL database of k3s was updated to version 14. Auto-upgrade is enabled from now on, the data automatically migrates to the new PostgreSQL major release.

### Mail server

Upstream NixOS mailserver introduced a `stateVersion` construct that requires migrations when updating to 25.11.
We run these migrations automatically, so you should not be required to take any action.
A downgrade back to 25.05 is no longer possible.
Read the [upstream release notes](https://nixos-mailserver.readthedocs.io/en/latest/release-notes.html#nixos-25-11) and
[migration guide](https://nixos-mailserver.readthedocs.io/en/latest/migrations.html#nixos-25-11) for more informations.

### Statshost

We migrated the login to the Grafana instance on statshosts from LDAP to OpenID Connect via auth.flyingcircus.io.
You can still use your credentials as normal on the new login page.

### Webgateway: nginx

With the transition to the NixOS upstream module, we removed two minor functionalities:

- Binary reload of nginx: We only update the nginx package during maintenance, and the benefits don't
  outweigh the additional complexity.
- Modifying the owner of log files with every reload and restart of nginx: All process involved in processing the log
  files already set the correct owner and permissions

We improved the scalability of the NixOS ACME service (available with `security.acme`).
Adding a new certificate to a VM doesn't cause all other ACME services to be triggered.
This leads to much faster deployment cycles for this case.

### Webproxy: Varnish

We now support configuring varnish listen addresses as structured config with the option
`services.varnish.listen`. The older option `services.varnish.http_address` is still available within the 25.11
release.`
For further information, please read the `services.varnish.listen` documentation.

### Network Protocol Metrics

Protocol-specific networking metrics have changed their name. Metrics of the scheme `net_$someProtocol_…` have been
deprecated and are replaced with an equivalent metric from the `nstat_$SomeProtocol…` name space. This reflects a change
in the Telegraf metrics collector used by our platform. \
For example: \
`net_udp_indatagrams` -> `nstat_UDP_InDatagrams`

#### What needs to be done

1. **Update dashboards** and other metrics consumers: modify your Grafana panels to query `nstat_*` metrics in addition.
2. **Keep legacy metrics temporarily**: Flying Circus NixOS ≥ 25.05 will emit both `net_` and `nstat_` metrics
   side‑by‑side for an overlap period.
3. **Remove legacy metrics**: once all hosts are running *Flying Circus NixOS ≥ 25.05* and the history of `nstat_*`
   metrics is at least a few months old, you can drop references to `net_*`. *Flying Circus NixOS 25.11* stops emitting
   the legacy `net_$someProtocol` metrics.

`nstat_*` metrics have similar names to their legacy equivalent and are easy to discover via Grafana’s **Explore** page.
Additionally,
the [Telegraf nstat plugin documentation](https://github.com/influxdata/telegraf/blob/v1.36.3/plugins/inputs/nstat/README.md#metrics)
lists all available metric names.

## Known issues

None.

## Significant package updates
