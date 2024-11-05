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

- New roles: {ref}`percona83 <nixos-upgrade-percona>`
- Removed roles: {ref}`percona81 <nixos-upgrade-percona>`
- Removed significant packages: `python38`
- Roles affected by significant breaking changes: none


## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 24.05 ends on **2024-12-31**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.


## How to upgrade?

At the moment, upgrading for customers is only possible by setting the platform
version using the API. Ask our [support](/platform/index.html#support) to
schedule an upgrade in a maintenance window or upgrade immediately if you don't
use the API.

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
versions. Here we assume that you are upgrading from the 23.11 platform.

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

(nixos-upgrade-percona)=

### Percona/ MySQL

Our Percona roles now reflect the upstream two-fold release model of the Percona
and Oracle MySQL projects of providing both an *LTS* release and a more short-lived
*Innovation* release in parallel. \
We still recommend using the LTS `percona80` for most use cases, see
{ref}`nixos-mysql-versions` for details.

### K3S

Machines created on NixOS 24.05 use k3s version 1.30.x. Machines upgraded
from earlier platform versions use 1.27.x of k3s by default which was also the
default for NixOS 23.11. Contact support if you want to use newer versions of k3s on these machines.

### Slurm

This release contains a major version upgrade of Slurm from 23.04.x.x (NixOS 23.11) to 23.11.x.x. Nodes of a cluster need to be upgraded in a prticular order, the the [upgrade instructions of the role](#nixos-slurm-upgrade) for details.

The default scheduler `SelectType` has been changed from `select/cons_res` to the default. As of now, this is `cons/tres`.

## Other notable changes

- `lamp` roles: Platform integration for the <https://tideways.com> application profiler has been dropped, the respective NixOS options are not available anymore.
- `inetutils` now has a lower priority to avoid shadowing the commonly-used `util-linux`. If one wishes to restore the default priority, simply use `lib.setPrio 5 inetutils` or override with `meta.priority = 5`.
- `pdns` was updated to version v4.9.x, which introduces breaking changes. Check out the Upgrade Notes for details.
- `openssh`, `openssh_hpn` and `openssh_gssapi` are now compiled without support for the DSA signature algorithm as it is being deprecated upstream. Users still relying on DSA keys should consider upgrading to another signature algorithm. However, for the time being it is possible to restore DSA key support by overriding the Nix package parameters, e.g. setting `openssh.override {dsaKeysSupport = true;}`.
- For more details, see the
  [release notes of NixOS 24.05](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-24.05-notable-changes).


## Significant package updates

*as of 2024-07-05*

- binutils: 2.40 -> 2.41
- bundler: 2.4 -> 2.5
- cmake: 3.27 -> 3.29
- coreutils: 9.3 -> 9.5
- curl: 8.4 -> 8.7
- docker-compose: 2.23 -> 2.27
- ffmpeg: 6.0 -> 6.1
- gcc: 12.3 -> 13.2 (older versions available under alias)
- ghostscript: 10.02 -> 10.03
- git: 2.42 -> 2.44
- gitlab: 16.10 -> 16.11
- glibc: 2.38 -> 2.39
- go: 1.21 -> 1.22 (1.21 remains available under alias)
- grafana: 10.2 -> 10.4
- k3s: see above
- kubernetes-helm: 3.13 -> 3.15
- libjpeg-turbo: 2.1 -> 3.0
- libressl: 3.8 -> 3.9
- libwep: 1.3 -> 1.4
- libxml2: 2.11 -> 2.12
- mailutils: 3.16 -> 3.17
- nginx: 1.24 -> 1.26
- nodejs: 18 -> 20 (older versions available under alias)
- openjdk: 19 -> 21 (older versions available under alias)
- opensearch: 2.11 -> 2.14
- openssh: 9.6p1 -> 9.7p1
- openvpn: 2.5 -> 2.6
- podman: 4.7 -> 5.0
- poetry: 1.7 -> 1.8
- postfix: 3.8 -> 3.9
- powerdns: 4.8 -> 4.9
- prometheus: 2.49 -> 2.52
- python3Packages.boto3: 1.28 -> 1.34
- python3Packages.pillow: 10.2 -> 10.3
- rsync: 3.2 -> 3.3
- systemd: 254 -> 255
