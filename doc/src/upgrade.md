(nixos-upgrade)=

# Platform Upgrades & What's New

Here you find information about changes compared to the previous platform
version, what to consider and where to take action before upgrading.

:::{note}
Before upgrading a machine, please read the {ref}`nixos-upgrade-general`
and {ref}`nixos-upgrade-breaking`.
Contact our {ref}`support` for upgrade assistance.
:::

(nixos-upgrade-overview)=

## Overview

- Removed roles: {ref}`postgresql11 <nixos-upgrade-postgresql>`, {ref}`mongodb42 <nixos-upgrade-mongodb>`
- Removed packages: `nodejs_14`, `nodejs_16`, `wkhtmltopdf`, `wkhtmltopdf_0_12_5`, `wkhtmltopdf_0_12_6`
- No major breaking changes
- Roles affected by significant changes:
  {ref}`postgresql15 <nixos-upgrade-postgresql>`,
  {ref}`rabbitmq <nixos-upgrade-rabbitmq>`


## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 23.11 ends on **2024-06-30**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.


## How to upgrade?

At the moment, upgrading for customers is only possible by setting the
platform version using the API. Ask our {ref}`support` to schedule an
upgrade in a maintenance window or upgrade immediately if you don't use the
API.

We are working on a feature to request upgrades from the customer self-service
portal.

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

We recommend upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 23.05 platform.

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
maintenance window to reduce impact on regular operations. VM may have
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

- None for this version.


(nixos-upgrade-postgresql)=

### PostgreSQL

- PostgreSQL 11 is not supported anymore as it reached its end of life.
  Upgrade to at least version 12 or preferably 15 as described in
  {ref}`nixos-postgresql-major-upgrade`.
- `services.postgresql.ensurePermissions` has been deprecated in favor of
  `services.postgresql.ensureUsers.*.ensureDBOwnership` which simplifies the
  setup of database owned by a certain system user in local database
  contexts (which make use of peer authentication via UNIX sockets),
  migration guidelines were provided in the NixOS manual, please refer to
  them if you are affected by a PostgreSQL 15 changing the way `GRANT ALL
  PRIVILEGES` is working. `services.postgresql.ensurePermissions` will be
  removed in 24.05.

(nixos-upgrade-mongodb)=

### MongoDB

`mongodb42` role and package have been removed. Machines that use MongoDB
should stay on 23.05 for now. We will bring back older MongoDB versions(up to
and including 4.2) for upgrading purposes only. As a long-term solution we
are evaluating [FerretDB](https://www.ferretdb.com/) which builds on
PostgreSQL and is compatible to MongoDB for many use cases.

(nixos-upgrade-rabbitmq)=

### RabbitMQ

`rabbitmq` is upgraded to 3.12. Before upgrading to NixOS 23.11, make sure that all
[Feature Flags](https://www.rabbitmq.com/feature-flags.html) are enabled.
3.12 requires **all** flags to be enabled or it won't start.

If all nodes in a cluster are the same version (3.11 on NixOS 23.05),
just enable all feature flags:

```shell
sudo -u rabbitmq rabbitmqctl enable_feature_flag all
```

## Other notable changes

- `python3` now defaults to Python 3.11.
- PHP now defaults to PHP 8.2, updated from 8.1. When using the `lamp` role,
  the default package changed from `lamp_php80` to `lamp_php82`.
- Upstream NixOS dropped support for PHP 8.0 as it is end-of-life. It is still
  useable on our platform but users should upgrade as soon as possible.
- `nodejs_14` and `nodejs_16` packages have been removed.
- Docker now defaults to version 24.
- `wkhtmltopdf` packages have been removed. They require a Qt version which
  has been unsupported for many years and wkhtmltopdf didn't get updates in a
  long time.
- Certificate generation via `security.acme` (used by the webgateway role) now
  limits the concurrent number of running certificate renewals and generation
  jobs, to avoid spiking resource usage when processing many certificates at
  once. The limit defaults to *5* and can be adjusted via
  `maxConcurrentRenewals`. Setting it to *0* disables the limits altogether.
- `services.github-runner` / `services.github-runners.<name>` gained the
  option `nodeRuntimes`. The option defaults to `[ "node20" ]`, i.e., the
  service supports Node.js 20 GitHub Actions only. The list of Node.js
  versions accepted by `nodeRuntimes` tracks the versions the upstream GitHub
  Actions runner supports.
- For more details, see the
  [release notes of NixOS 23.11](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-23.11-notable-changes).


## Significant package updates

- curl: 8.1 -> 8.4
- docker: 20.10 -> 24.0
- docker-compose: 2.18 -> 2.23
- git: 2.40 -> 2.42
- glibc: 2.37 -> 2.38
- grafana: 9.5 -> 10.2
- haproxy: 2.7 -> 2.8
- k3s: 1.26 -> 1.27
- keycloak: 21.1 -> 22.0
- kubernetes-helm: 3.11 -> 3.13
- mastodon: 4.1 -> 4.2
- nginxMainline: 1.24 -> 1.25
- nix: 2.13 -> 2.18
- opensearch: 2.6 -> 2.11
- opensearch-dashboards: 2.6 -> 2.11
- openssh: 9.3 -> 9.5
- phpPackages.composer: 2.5 -> 2.6
- podman: 4.5 -> 4.7
- poetry: 1.4 -> 1.7
- powerdns: 4.7 -> 4.8
- prometheus: 2.44 -> 2.48
- redis: 7.0 -> 7.2
- sudo: 1.9.13p3 -> 1.9.15p2
- systemd: 253 -> 254
- util-linux: 2.38 -> 2.39
- varnish: 7.2 -> 7.4
- zlib: 1.2.13 -> 1.3
