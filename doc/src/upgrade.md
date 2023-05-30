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

- Status: staging/non-production
- Removed roles: {ref}`elasticsearch6, elasticsearch7 <nixos-upgrade-elasticsearch>`, `mongodb36`, `mongodb40`


## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

We do back-ports for critical security issues but this may take longer in some
cases and less important security fixes will not be back-ported most of the time.

NixOS provides regular security updates for about one month after the release.
Upstream support for 23.05 ends on **2023-12-31**.

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

- `libxcrypt`, the library providing the `crypt(3)` password hashing function,
  is now built without support for algorithms not flagged[`strong`]
  (https://github.com/besser82/libxcrypt/blob/v4.4.33/lib/hashes.conf#L48)
  in NixOS 23.05. We added a variant package called `libxcrypt-with-sha256`
  which also enables the `sha256` algorithm. OpenLDAP, Dovecot, Postfix,
  cyrus_sasl use that version by default. New password hashes should use
  strong algorithms like `yescrypt`.
- `podman` now uses the `netavark` network stack. Users will need to delete
  all of their local containers, images, volumes, etc, by running `podman
  system reset --force` once before upgrading their systems.


(nixos-upgrade-elasticsearch)=

### Elasticsearch

`elasticsearch6` and `elasticsearch7` roles have been removed. Machines that use these
roles should stay on 22.11 and migrate to Opensearch before upgrading.

## Other notable changes

- NixOS now defaults to using nsncd (a non-caching reimplementation in Rust)
  as NSS lookup dispatcher, instead of the buggy and deprecated
  glibc-provided nscd.
- The `NodeJS` packages have been renamed to a more usual naming scheme,
  for example `nodejs-19_x` is now `nodejs_19`.
- The `dnsmasq` service now takes configuration via the
  `services.dnsmasq.settings` attribute set. The option
  `services.dnsmasq.extraConfig` still works but should be migrated to
  `settings` soon. `extraConfig` is deprecated in this release
  and issues warnings at system build time.
- PostgreSQL has opt-in support for [JIT compilation]
  (https://www.postgresql.org/docs/current/jit-reason.html). It can be
  enabled like this:
  ```nix
  {
    services.postgresql = {
      enableJIT = true;
    };
  }
  ```
- `openjdk` from version 11 and above is not build with `openjfx`
  (i.e.: JavaFX) support by default anymore. You can re-enable it by
  overriding, e.g.: `openjdk11.override { enableJavaFX = true; };`.
- A new option `recommendedBrotliSettings` has been added to `services.nginx`.
  Learn more about compression in Brotli format [here](https://github.com/google/ngx_brotli/blob/master/README.md).
- `vim_configurable` has been renamed to `vim-full` to avoid confusion:
  `vim-full`'s build-time features are configurable, but both `vim` and
  `vim-full` are _customizable_ (in the sense of user configuration, like
  vimrc).
- For more details, see the
  [release notes of NixOS 23.05](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-23.05-notable-changes).


## Significant package updates

- asterisk: 19.8.0 -> asterisk-20.2.1
- bash: 5.1 -> 5.2
- binutils: 2.39 -> 2.40
- bundler: 2.3 -> 2.4
- curl: 7.86.0 -> 8.0
- dnsmasq: 2.87 -> 2.89
- docker-compose: 2.12 -> 2.17
- ffmpeg: 4.4.2 -> 5.1
- gcc: 11 -> 12
- git: 2.38 -> 2.40
- glibc: 2.35 -> 2.37
- grafana: 9.4 -> 9.5
- haproxy: 2.6 -> 2.7
- k3s: 1.25 -> 1.26
- kubernetes-helm: 3.10 -> 3.11
- linux: 5.15 -> 6.1
- nginx: 1.22 -> 1.24
- nss-cacert: 3.86 -> 3.89
- openjdk: 17 -> 19 (same for other Java default packages like `jre`)
- openssh: 9.1 -> 9.3
- podman: 4.3 -> 4.5
- rabbitmq-server: 3.10 -> 3.11
- ruby: 2.7 -> 3.1
- systemd: 251 -> 253
- telegraf: 1.24 -> 1.26
- xfsprogs: 5.19 -> 6.2
