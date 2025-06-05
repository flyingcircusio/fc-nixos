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

- New roles: {ref}`percona84 <nixos-upgrade-percona>`
- Removed roles:
- Removed significant packages: `dstat`, `latencytop`, `atop`
- Roles affected by significant breaking changes: {ref}`gitlab <nixos-upgrade-gitlb>`, {ref}`k3s-agent k3s-server k3s-single-node <nixos-upgrade-k3s>`


## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 24.11 ended on **2025-06-31**.

New platform features are always developed for the current stable platform version
and only critical bug fixes are back-ported to older versions.


## How to upgrade?

To upgrade your machines, the *Environment* to one of the `fc-25.05-…`
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

We recommend upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 24.11 platform.

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
maintenance window to reduce impact on regular operations. A VM may have
degraded performance for some minutes when packages are being downloaded and
built.

With NixOS, the switch to the new system happens after a successful system
build so most services are unavailable at the same time and only for a small
time-window.

(nixos-upgrade-breaking)=

## Significant breaking changes

(nixos-upgrade-percona)=
### Percona/ MySQL

TODO percona84 LTS
TODO percona auth changes

(nixos-upgrade-postgresql)=
### Postgresql

TODO prostgres17?

(nixos-upgrade-k3s)=
### K3S

k3s-1.32.x is the default k3s version in this release.

TODO

XXX
Clusters that were created on the NixOS 24.11 platform already use that version.
Clusters created at an earlier release might still be using an older k3s version,
please verify that they are upgraded to k3s-1.30.x before upgrading to NixOS 24.11.

k3s nodes are only allowed to be updated ins steps of one minor version at a time.
The Kubernetes control plane with the `k3s-server` role needs to be updated before
the cluster's worker nodes with the `k3s-agent` role are updated.

Contact support of you need help with updating your k3s cluster, or if you still
need to use another specific k3s version for your cluster.

(nixos-upgrade-slurm)=
### Slurm

TODO

This release contains a major version upgrade of Slurm from 23.11.x.x (NixOS 24.05) to 24.05.x.x. Nodes of a cluster need to be upgraded in a particular order, please consult the [upgrade instructions of the role](#nixos-slurm-upgrade) for details.

(nixos-upgrade-docker)=
### Docker

The default docker version is updated from 24 to 27. Some of the major changes are:

- The `devicemapper` storage driver is not supported anymore. See {ref}`nixos-docker-storage-driver` for background information and instructions on how to migrate your existing containers before upgrading.
- docker-27 finally supports IPv6 networking by default. While this enables more modern networking setups, please ensure that your service security does not rely on the implicit assumption that containers have no IPv6 networking.
- Read-only bind mounts are **recursively read-only** by default [since docker-25](https://docs.docker.com/engine/release-notes/25.0/#2500).


(nixos-upgrade-gitlab)=
### Gitlab

## Other notable changes

TODO

- Nix was upgraded to version 2.28
- For more details, see the
  [release notes of NixOS 25.05](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-25.05).


## Significant package updates

TODO

*as of 2025-01-31*
