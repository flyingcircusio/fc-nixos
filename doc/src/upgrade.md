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
  - `postgresql19`
- Removed roles:
  - {ref}`postgresql14 <nixos-upgrade-postgresql>`
- Removed significant packages:
  - `awscli`
  - `calibre`
  - `k3s_1_33`
  - `openssl_1_1`
  - `openssl_3_6`
  - `openssl_4_0`
  - `php72`
  - `php73`
  - `postgresql_14`
  - `varnish`

## Why upgrade? Security

Upgrading to the latest platform version as soon as possible is important to
get all security package updates and other security-related improvements
provided by NixOS (our "upstream" distribution we build on).

NixOS provides regular security updates for about one month after the release.
Upstream support for 26.05 ends on **2026-12-31**, upstream support for 26.11 ends on **2027-06-30**.

New platform features are always developed for the current stable platform version.
Only very critical bug and security fixes are backported to older platform versions that are out of support upstream.

## How to upgrade?

To upgrade your machines, the *Environment* to one of the `fc-26.11-…`
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

Upgrades should always be checked in a staging environment first.
For managed deployments, our AppOps team coordinates this update,
for guided and hosted VMs, please update yourself.

### Upgrade to the next platform version

We strongly advise upgrading platform versions one at a time without skipping
versions. Here we assume that you are upgrading from the 26.05 platform.
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

### Service memory configuration

We changed how memory configuration works for all roles.
This affects **elasticsearch, mariadb, matomo, opensearch, percona (mysql), postgresql, redis, webproxy (vinyl cache)**.

Memory percentage NixOS options are now calculated based on the memory of the VM available to services, i.e. the current memory of the VM minus the overhead as defined in https://doc.flyingcircus.io/platform/infrastructure/vms/index.html#minimum-memory-requirements-nixos-based-vms-only.

This affects the following options:

- elasticsearch: `flyingcircus.roles.elasticsearch.heapPercentage`
- mariadb: `flyingcircus.roles.mariadb.bufferMemoryPercentage`
- opensearch: `flyingcircus.roles.opensearch.heapPercentage` / `flyingcircus.services.opensearch.heapPercentage`
- percona: `flyingcircus.roles.mysql.bufferMemoryPercentage`
- redis: `flyingcircus.services.redis.memoryPercentage`
- webproxy: `flyingcircus.roles.webproxy.mallocMemoryPercentage`

After upgrading **services will allocate less memory than before!**
You can change the configuration already before the upgrade. Here is an example how to do this with percona:

```nix
{ config, lib, ... }: {
  # If you also want to set a custom value for the system with 26.11
  flyingcircus.roles.mysql.bufferMemoryPercentage = if (lib.versionAtLeast config.system.nixos.release "26.11") then 80 else 15;

  # If you want to use the default on 26.11
  flyingcircus.roles.mysql.bufferMemoryPercentage = lib.mkIf (lib.versionOlder config.system.nixos.release "26.11") 15;
}
```

Virtual machines with less than 2.5 GiB of memory are not affected by this change.
As these are below our defined system overhead, we use the old method and don't include the defined overhead in calculations for services.

### LAMP

#### Correct escaping of PHP-FPM options

Configuration options of PHP-FPM are now correctly escaped.
This leads to a change that booleans written as a string, e.g. "true" and "false" are now also written as `"true"` and `"false"` instead of `true` and `false` in the PHP-FPM INI config file. Integers written as a string before in the Nix config, e.g. `"8"`, are now also written as `"8"` instead of `8` in the INI configuration file. Please migrate to the correct types in the NixOS configuration.
This change affects the configuration options:

- `flyingcircus.roles.lamp.vhosts.<...>.pool.extraConfig`
- `flyingcircus.roles.lamp.vhosts.<...>.pool.phpEnv`
- `flyingcircus.roles.lamp.vhosts.<...>.pool.settings`
- `services.phpfpm.pools.<...>.extraConfig`
- `services.phpfpm.pools.<...>.phpEnv`
- `services.phpfpm.pools.<...>.settings`
- `services.phpfpm.extraConfig`
- `services.phpfpm.settings`

#### Structured php.ini config

Using a string for specifying `php.ini` settings is deprecated and will be removed with fc-nixos 27.05.
This release still supports the configuration using strings and will output a warning for a simple migration.
This affects the configuration options

- `flyingcircus.roles.lamp.php_ini`
- `flyingcircus.roles.lamp.vhosts.<...>.pool.phpOptions`
- `services.phpfpm.pools.<...>.phpOptions`
- `services.phpfpm.phpOptions`

For example the previous configuration

```nix
flyingcircus.roles.lamp.php_ini = ''
  upload_max_filesize = 200M
  post_max_size = 200M
  date.timezone = Europe/Berlin
'';
```

should now be written as

```nix
flyingcircus.roles.lamp.php_ini = {
  "upload_max_filesize" = "200M";
  "post_max_size" = "200M";
  "date.timezone" = "Europe/Berlin";
};
```

This change also allows easier overriding of the `php.ini` settings per pool.

#### Version changes

PHP 7.2 and 7.3 have been removed as they are end-of-life for a prolonged period of time.

PHP 8.2 also reached its end-of-life. While we still provide it, please upgrade at your earliest convenience.

The new default PHP version for the lamp role is 8.5.

## GitLab

The database metadata backend for the container registry is now enabled by default on new installations.
Existing installations get prepared, i.e. a database is created by default and GitLab container registry connects to it
and uses it only when the whole filesystem metadata storage was migrated to the database.

New installations also use the `gitlab-container-registry` system user for the GitLab container registry
instead of the `docker-registry` user. This behavior can be modified with the `services.gitlab.registry.user` option.

(nixos-upgrade-k3s)=

### k3s

The default `k3s` package has been bumped to 1.34. Existing clusters may
need to be updated to this version before upgrading cluster VM's to the 26.11
platform. See the role documentation for {ref}`cluster version updates
<nixos-k3s-update-versions>`.

### Webproxy (Vinyl Cache / Varnish Cache)

The support for Varnish Cache has been removed.
Please migrate to Vinyl Cache 9.
Configuring Vinyl Cache 9 via `/etc/local/varnish/default.vcl` is still supported throughout this release.

Vinyl Cache has been updated to 9.1. This includes some rare breaking changes, see the [upstream upgrade guide](https://vinyl-cache.org/docs/9.1/whats-new/upgrading-9.1.html) for more information.

(nixos-upgrade-slurm)=

### Slurm

This release contains a major version upgrade of Slurm from 25.11.x.x (NixOS 26.05) to 26.11.x.x. Nodes of a cluster
need to be upgraded in a particular order, please consult the [upgrade instructions of the role](#nixos-slurm-upgrade)
for details.

Regarding new features or changes in Slurm itself,
consult [its release notes](https://github.com/SchedMD/slurm/blob/slurm-26-05-6-1/RELEASE_NOTES.md).

(nixos-upgrade-postgresql)=

### PostgreSQL

The `postgresql14` role has been removed, as it's end-of-life. Please update to `postgresql15` or newer.

`postgresql19` is now available. Please read the [upstream release notes](https://www.postgresql.org/docs/release/19.0/) for more information.

The option to PostgreSQL via local plain config in `/etc/local/postgresql/<version>/*.conf` has been removed.
This has been deprecated since fc-nixos 20.09.
Please use Nix-based structured config using the `services.postgresql.settings` option.

### Tempo

Tempo was updated from 2.10 to 3.1. Our role has updated its config, however custom configuration needs to be adjusted.
Read the section for monolithic deployments in the [migration notes](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/migrate-to-3/), the [upgrade notes](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/upgrade/) and [release notes](https://grafana.com/docs/tempo/latest/release-notes/v3-0/) of Tempo.

## Other notable changes

- The `security.dhparams` module has been removed. Remove any uses of DHE and migrate to ECDHE (RFC 8422, 2018) and Hybrid PQ (draft-ietf-tls-ecdhe-mlkem, 2026) key exchange algorithms.
- The `python2` and `python27` packages has been removed.
- The `openssl_1_1` and `openssl_3` packages has been removed.
- The current logrotate config can now be found in `/etc/logrotate.conf` instead of `/etc/current-config/logrotate.conf`.
  With that, the `logrotate-show-config` command has been deprecated and removed.
- PostgreSQL Anonymizer now only allows applying masking rules by users without the `SUPERUSER` privilege. This can be changed as described in [the upstream documentation](https://postgresql-anonymizer.readthedocs.io/en/stable/configure/)
- The mailserver role now stores the sieve scripts inside the users mail directory instead of in `/var/sieve`. The migration happens automatically after update.
- The sieve listener of the mailserver role now listens with TLS only instead of plain text with STARTTLS.
  STARTTLS may be re-enabled at your own security risk with `mailserver.listeners.manageSieve.ssl`.


## Known issues

- The `ai-model-server` role currently doesn't work, as VLLM with CUDA support is currently broken in Nixpkgs

## Significant package updates

* `automake`: 1.18.1 -> 1.19
* `awscli` removed, use `awscli2`
* `awscli2`: 2.34.24 -> 2.36.31
* `bash`: 5.3p9 -> 5.3p20
* `bind`: 9.20.30 -> 9.20.31
* `calibre` removed
* `ceph`: 14.2.22 -> 16.2.15
* `chromedriver`: 158.0.8127.36 -> 158.0.8127.88
* `chromium`: 158.0.8127.36 -> 158.0.8127.88
* `cifs-utils`: 7.5 -> 7.9
* `clamav`: 1.4.6 -> 1.5.5
* `cmake`: 4.1.6 -> 4.5.0
* `containerd`: 2.3.3 -> 2.4.1
* `coreutils`: 9.11 -> 9.12
* `coturn`: 4.16.0 -> 4.17.2
* `crowdsec`: 1.8.1 -> 1.8.2
* `discourse`: 2026.9.2 -> 2026.10.2
* `docker-compose`: 5.6.1 -> 5.7.1
* `erlang`: 28.5.0.8 -> 28.5.0.9
* `fetchmail`: 6.6.3 -> 6.6.7
* `ffmpeg`: 8.1.3 -> 9.0.2
* `file`: 5.47 -> 5.48
* `firefox`: 160.0.1 -> 161.0
* `gcc`: 15.3.0 -> 16.2.0
* `git`: 2.54.0 -> 2.56.1
* `glibc`: 2.42 -> 2.44
* `go`: 1.26.10 -> 1.27.4
* `grafana`: 13.0.13 -> 13.3.1
* `grub2`: 2.12.1 -> 2.14
* `haproxy`: 3.3.17 -> 3.4.8
* `imagemagick`: 7.1.2-35 -> 7.1.2-36
* `iperf3`: 3.20 -> 3.21
* `jetbrains.jdk`: 25.0.2-b329.72 -> 25.0.5.1-b635.102
* `jetty`: 12.1.10 -> 12.1.14
* `jicofo`: 1.0-1153 -> 1.0-1205
* `jitsi-meet`: 1.0.8792 -> 1.0.9365
* `jitsi-videobridge`: 2.3-249-g9a2123ad4 -> 2.3-358-gf8efaa72c
* `k3s_1_33` removed
* `k3s_1_37`: initialized at 1.37.2+k3s1 (new)
* `k3s`: 1.35.10+k3s1 -> 1.36.6+k3s1
* `kubernetes-helm`: 3.20.2 -> 4.3.2
* `libjpeg`: 3.1.4 -> 3.2.1
* `libmodsecurity`: 3.0.14 -> 3.0.17
* `libressl`: 4.2.3 -> 4.4.1
* `linuxKernelGPU`: 6.18.64 -> 6.18.65
* `linuxKernelStable`: 6.18.64 -> 6.18.65
* `linuxKernelVerify`: 6.18.64 -> 6.18.65
* `mastodon`: 4.6.12 -> 4.7.6
* `mstflint`: 4.36.0-1 -> 4.37.0-1
* `nfs-utils`: 2.9.1 -> 3.2.1
* `nginx`: 1.30.7 -> 1.30.8
* `nginxMainline`: 1.31.9 -> 1.31.10
* `nginxStable`: 1.30.7 -> 1.30.8
* `nix`: 2.34.9 -> 2.35.6
* `openssl_1_1` removed
* `openssl_3_6` removed
* `openssl_4_0` removed
* `openssl_4_1`: initialized at 4.1.0 (new)
* `openssl_legacy` removed
* `openssl`: 3.6.5 -> 3.5.9
* `pcre` removed
* `pdns`: 5.0.8 -> 5.1.5
* `percona-server_8_4`: 8.4.10-10 -> 8.4.11-11
* `percona-server`: 8.4.10-10 -> 8.4.11-11
* `percona-xtrabackup_8_4`: 8.4.0-4 -> 8.4.0-7
* `php72` removed
* `php73` removed
* `phpPackages.composer`: 2.10.3 -> 2.11.3
* `podman`: 5.8.9 -> 6.1.4
* `poetry`: 2.4.1 -> 2.5.2
* `polkit`: 127 -> 128
* `postfix`: 3.11.7 -> 3.11.8
* `postgresql_14` removed
* `postgresql_19`: initialized at 19.0 (new)
* `postgresql`: 17.12 -> 18.7
* `postgresql14Packages.postgis` removed
* `postgresql14Packages.temporal_tables` removed
* `prometheus`: 3.12.0 -> 3.16.0
* `prosody`: 13.0.6 -> 13.0.7
* `python3`: 3.13.18 -> 3.14.10
* `python3Packages.boto3`: 1.42.31 -> 1.43.79
* `python3Packages.click`: 8.3.1 -> 8.5.1
* `python3Packages.lxml`: 6.0.2 -> 6.1.3
* `python3Packages.pip`: 25.3 -> 26.2.2
* `python3Packages.requests`: 2.33.1 -> 2.34.2
* `python3Packages.rich-rst`: 1.3.2 -> 2.1.0
* `python3Packages.rich`: 14.3.3 -> 15.0.0
* `python3Packages.structlog`: 25.5.0 -> 26.1.0
* `qemu-ceph-nautilus` removed
* `qemu-ceph-pacific`: 10.2.4 -> 11.1.2
* `rabbitmq-server`: 4.2.9 -> 4.3.1
* `re2c`: 4.5.1 -> 4.6
* `redis`: 8.8.4 -> 8.10.3
* `roundcube`: 1.7.6 -> 1.7.7
* `ruby`: 3.4.12 -> 3.4.13
* `runc`: 1.4.3 -> 1.5.3
* `screen`: 5.0.1 -> 5.0.2
* `slurm`: 25-11-8-1 -> 26-05-6-1
* `sysstat`: 12.7.7 -> 12.8.1
* `systemd`: 260.5 -> 262.2
* `tcpdump`: 4.99.6 -> 4.99.7
* `telegraf`: 1.38.4 -> 1.40.4
* `tmux`: 3.7b -> 3.8
* `tomcat10`: 10.1.55 -> 10.1.61
* `tomcat9`: 9.0.123 -> 9.0.124
* `unifi`: 10.2.105 -> 10.6.111
* `uv`: 0.11.21 -> 0.13.9
* `varnish` removed
* `vinyl-cache_9`: 9.0.2 -> 9.1.0
* `vinyl-cache`: 9.0.2 -> 9.1.0
* `xfsprogs`: 6.19.0 -> 7.2.1
* `zlib`: 1.3.2 -> 1.4
* `zsh`: 5.9.1 -> 5.9.2
