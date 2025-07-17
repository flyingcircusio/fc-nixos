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
  - {ref}`percona84 <nixos-upgrade-percona>`
  - {ref}`postgresql17 <nixos-upgrade-postgresql>`
- Removed roles: none
- Roles affected by significant breaking changes:
  - {ref}`gitlab <nixos-upgrade-gitlab>`
  - {ref}`k3s-agent k3s-server k3s-single-node <nixos-upgrade-k3s>`
  - {ref}`mailserver mailstub <nixos-upgrade-mail>`
  - {ref}`redis <nixos-upgrade-redis>`
  - {ref}`percona84 <nixos-upgrade-percona>`
  - {ref}`slurm-controller slurm-node <nixos-upgrade-slurm>`
- Removed significant packages:
  - `atop`
  - `dstat`
  - `go_1_22`
  - `k3s_1_29`
  - `latencytop`
  - `nodejs_18`
  - `python39`


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

(nixos-upgrade-percona)=
### Percona/ MySQL

Two versions of percona are actively supported: `percona80` and `percona84`. \
Both are LTS releases still receiving bug and security fixes.

`percona83` is only included to allow upgrades towards `percona84`.

#### no password authentication for root user (all role versions)

Access to the database `root` user was changed to authentication via socket.
Password authentication is disabled for that user, please switch to the unix user `mysql` for database root operations.

The platform used to provide the password for the database root user under `/etc/local/mysql/mysql.passwd`. That
file does not exist anymore. Instead, invoke your mysql command via `sudo -u mysql`. \
Example:

```shell
sudo -u mysql mysql myDb < someCommands.sql
```

Users of `batou.lib.mysql` can just [pass `USE_SUDO` as the `admin_password` argument](https://github.com/flyingcircusio/batou/commit/7efcb768613f1d68699defa453c0634a279b98be).

#### changed authentication mechanism in percona84

Version 8.4 of percona (role `percona84`) changes the default authentication mechanism from `mysql_native_password` to `caching_sha2_password`. After upgrading the role to 8.4. *all passwords need to be migrated manually* to the new hash format.

Please do the migration during this platform release cycle, our 25.11 platform with Percona 9.x will disable the deprecated hashing algorithm altogether.

See {ref}`nixos-mysql-password-hash-migration` for detailed migration instructions.

(nixos-upgrade-postgresql)=
### PostgreSQL

PostgreSQL version 17 is available as a new `postgresql17` role.
There are no breaking changes in the integration of PostgreSQL into the Flying Circus platform, but the database software itself includes some major changes listed [in its Release Notes](https://www.postgresql.org/docs/release/17.0/).
Migrating between major versions of PostgreSQL requires migrating the data directory. See {ref}`nixos-postgresql-major-upgrade` for how out platform can help with that.

All existing major versions of the postgresql role remain available.



(nixos-upgrade-k3s)=
### K3S

k3s-1.32.x is the default k3s version in this release.

Please verify that existing clusters are upgraded to k3s-1.30.x **before** upgrading to NixOS 25.05.

k3s nodes are only allowed to be updated in steps of one minor version at a time.
The Kubernetes control plane with the `k3s-server` role needs to be updated before
the cluster's worker nodes with the `k3s-agent` role are updated.

Contact [support](/platform/index.html#support) if you need help with updating your k3s cluster, or if you still
need to use another specific k3s version for your cluster.

(nixos-upgrade-slurm)=
### Slurm

This release contains a major version upgrade of Slurm from 24.05.x.x (NixOS 24.11) to 24.11.x.x. Nodes of a cluster need to be upgraded in a particular order, please consult the [upgrade instructions of the role](#nixos-slurm-upgrade) for details.

Regarding new features or changes in Slurm itself, consult [its release notes](https://github.com/SchedMD/slurm/blob/slurm-24-11-0-1/RELEASE_NOTES).


(nixos-upgrade-gitlab)=
### Gitlab

Gitlab version 18.0 will enable pseudonymised [tracking and reporting of events data](https://about.gitlab.com/blog/2025/03/26/more-granular-product-usage-insights-for-gitlab-self-managed-and-dedicated/). To prevent this, an **opt-out** can already be configured in the current Gitlab version:
- Visit `<yourgitlabdomain>/admin/application_settings/metrics_and_profiling`
- uncheck *Event tracking -> Enable event tracking*

Postgresql>=16 is required, please upgrade your postgres role before updating.

*Runner registration tokens* have been deprecated for several releases already and are not supported anymore in Gitlab 18.
Our [support](/platform/index.html#support) staff will take care of migrating your managed Gitlab instance to the new *runner authentication token scheme* ahead of the update. For advanced use cases like interactions between Gitlab and external runners not part of the Flying Circus platform, please reach out to our support.

(nixos-upgrade-mail)=
### Mailserver, mailstub

Both `mailserver` and `mailstub` roles are affected by changes in the underlying implementations:
- DKIM signing and verification is now handled by rspamd instead of OpenDKIM. rspamd only supports `relaxed` canoncalisation.
- `policyd-spf` was removed, SPF record verification of incoming mails is handled by rspamd.
  - The `policydSPFExtraSkipAddresses` option has been renamed to `spfSkipAddresses`, reflecting that change.
  - `mailserver.policydSPFExtraConfig` was removed.
- `flyingcircus.roles.mailserver.imprintUrl` now requires a full URI starting with the `http://` or `https://` protocol. Protocol-less URIs had been deprecated in the 24.11 platform release.

(nixos-upgrade-redis)=
### Redis

- redis: restructure internal password handling
  The password file /etc/local/redis/password now gets written as systemd ExecStartPre. (PL-133653)

  `services.redis.servers."".requirePass` must not be used anymore. There are three options to replace it with:
    - `services.redis.servcers."".requirePassFile` to retrieve the password from an external file
    - set `flyingcircus.services.redis.password`
    - just remove the option, causing the password to be autogenerated and stored at `/etc/local/redis/password`.  \
      Autogenerated passwords can not be read from the Nix config at evaluation time.
- reading the Redis password at evaluation time from `config.flyingcircus.services.redis.password` is not supported anymore.

### changes not affecting a specific role

% does not affect our platform MongoDB roles but things set up by AppOps via the nixpkgs service
- mongodb: The option `services.mongodb.initialRootPassword` was removed in favour of `services.mongodb.initialRootPasswordFile` to securely provide the initial root password.
- postgresql: `pg_config` has been moved to a separate package `postgresql.pg_config` or `postgresql_<major version>.pg_config`. Packages and environment relying on the presence of that command need to explicitly specify that package as a dependency.
  - Building other software against postgresql usually also requires libraries and headers as well, so in general the following dependencies need to be specified:
    * `postgresql.pg_config.out`
    * `postgresql.out`
    * `postgresql.lib`
    * `postgresql.dev`
  - For deplyoments using a [batou_ext userenv](https://github.com/flyingcircusio/batou_ext/blob/98cba22c8fe4c8cf6273855704673161bf108336/src/batou_ext/nix.py#L110), only `postgresql.pg_config` and `postgresql` are required.

## Other notable changes

- Nix was upgraded to version 2.28
- agent: the command `fc-manage switch` now has a `-R` option which
  will activate the new configuration by performing an immediate
  reboot, similar to the process used for upgrading between major
  versions. (PL-133308)
- improvements in configuring the nixpkgs package set:
  - Introduced option `flyingcircus.permittedInsecurePackages` to allow additional packages marked as insecure.
  - Improved error message when trying to use a package marked as insecure or unfree showing FCIO-specific instructions.
  - When importing the platform channel (`import <fc> …`), declarations of `config.allowUnfreePredicate` and
  `config.permittedInsecurePackages` don't get discarded silently. In case of `allowUnfreePredicate`, at least
  one of the platform-provided or user-supplied predicate must evaluate to `true` to allow the instantiation of
  an unfree package.
- docker: fix role not working on devhosts (PL-133607)

  This change also prepares the role to work on machines without FE interface or PUB interface.

- We added a mechanism to upgrade XFS flags over time. This is disabled by default (see warning).

  At the moment this will cause the `bigtime`, `inobtcount` and `nrext64` flags to be set.
  With `bigtime` set VMs will consistently support file times beyond 2038, even if
  they were bootstrapped on older releases. (PL-133321, PL-130365)

  :::{warning}

  With large disks or many files and inodes, this process can take several (tens
  of) minutes. As this migration step is done during the early boot phase, the
  machine won't be available for that time at the first boot after upgrading.

  We are working on another implementation that will schedule separate maintenances
  and predict downtimes more accurately and will speed up the process.

  If you need to upgrades and your machine has an especially large disk of
  >500GB, please contact [support](/platform/index.html#support) before enabling
  the `flyingcircus.initrd.enableXFSUpgrades` option.

  :::

- Prepare VMs to read ENC data (the config management metadata) seeded from the
  host from the separate `cidata` volume in the future. This allows disabling or
  reconfiguring /tmp to use tmpfs without breaking our configuration management.
  (PL-133311)
- Invalid NixOS `state_version` files are automatically fixed to fit the expected YY.MM format. (PL-133559)
- nginx: new JSON-based log format that is being used to ship access logs to a Loki instance automatically if one is present (PL-133702)
- dstat: drop as it is unmaintained, replace with `dool`
  - `dstat` is now an alias for `dool`
- `less` does not utilise external programs to improve rendering by default (lesspipe). To restore the previous behaviour, set `programs.less.lessopen` to `''|${lib.getExe' pkgs.lesspipe "lesspipe.sh"} %s''`.
- linux kernel: we now follow the 6.12.x LTS series of linux for production environments. This seems to help resolve some recent IO latency / stalling issues.
- Kernel memory management: switch to smaller, fixed size dirty page buffers (PL-133760)

  This also seems to be a factor in the recent IO latency / stalling issues:
  The dirty page buffers were based on percentages of the installed RAM so far,
  but can cause long periods of stalling when the kernel passes the hard
  threshold to flush it.

  We now provide much smaller and fixed sizes for dirty pages (16 MiB to start
  flushing in the background and 64 MiB to enforce flushing).
- For more details, see the
  [release notes of NixOS 25.05](https://nixos.org/manual/nixos/stable/release-notes.html#sec-release-25.05).

## Known issues

- mailserver: Incoming e-mails via IPv4 are treated as local e-mails by rspamd, skipping SPF, DKIM, and DMARC checks

## Significant package updates

*as of 2025-06-24*

- awscli: 1.34 -> 1.37
- awscli2: 2.19 -> 2.27
- binutils: 2.43 -> 2.44
- calibre: 7.21 -> 8.4
- containerd: 1.7 -> 2.1
- coreutils: 9.5 -> 9.7
- curl: 8.12 -> 8.13
- discourse: 3.3 -> 3.4
- docker-compose: 2.30 -> 2.36
- erlang: 25.3 -> 27.3
- gcc: 13.3 -> 14.2 (other versions available under alias)
- git: 2.47 -> 2.49
- gitlab: 17.11 -> 18.0
- go: 1.23 -> 1.24 (other versions available under alias)
- grafana: 11.3 -> 12.0
- haproxy: 3.0 -> 3.1
- k3s: 1.30 -> 1.32 (other versions available under alias)
- kubernetes-helm: 3.16 -> 3.17
- libwebp: 1.4 -> 1.5
- linux: 6.6 -> 6.12
- matomo: 5.2 -> 5.3
- nginx: 1.26 -> 1.28
- nodejs: 20 -> 22 (other versions available under alias)
- opensearch: 2.17 -> 2.19
- openssh: 9.9 -> 10.0
- openssl: 3.3 -> 3.4
- podman: 5.2 -> 5.4
- poetry: 1.8 -> 2.1
- postfix: 3.9 -> 3.10
- prometheus: 2.55 -> 3.1
- python3Packages.boto3: 1.35 -> 1.36
- python3Packages.rich: 13.8 -> 14.0
- rclone: 1.68 -> 1.69
- re2c: 3.1 -> 4.1
- slurm: 24.05 -> 24.11
- systemd: 256 -> 257
- telegraf: 1.32 -> 1.34
- util-linux: 2.39 -> 2.41
- uv: 0.4 -> 0.7
- varnish: 7.5 -> 7.7
- xz: 5.6 -> 5.8
