# Release 2024_035


## Impact

- None.

## NixOS XX.XX platform

- Internal: Introduce automatic nixpkgs update workflow (PL-133100)

- The `fc-postgresql` command now supports upgrades of databases with preinstalled extensions:
  - When upgrading manually with `fc-postgresql`, add `--extension-names ext1 --extension-names ext2` to the command line. `ext1`/`ext2` must be the package names of the extensions without the `postgresqlPackages.`-prefix. Usually it's the packages in [`services.postgresql.extraPlugins`](https://search.flyingcircus.io/search/options?q=services.postgresql.extraPlugins&channel=fc-24.05-dev#services.postgresql.extraPlugins).
  - When using automatic upgrades ([`flyingcircus.services.postgresql.autoUpgrade.enable `](https://search.flyingcircus.io/search/options?q=+flyingcircus.services.postgresql.autoUpgrade.enable+&channel=fc-24.11-dev&page=1#flyingcircus.services.postgresql.autoUpgrade.enable)), existing extensions will be discovered automatically. You don't have to do anything in this case.

- Fix a bug in the reload script for the varnish service that only occurs when there are cold VCLs to be discarded. An error in the templating would lead to attempting to run a varnish admin instruction (vcl.discard in this case) as a shell command. (PL-133251)

- S3 users are now managed automatically and can be viewed and managed via our
  customer portal. (PL-133084)

- Fix systemd units managing flooding suppression and MAC learning
  configuration so that settings are restored to their defaults when
  the units are stopped. (PL-133202)

- Add sensu check on routers to monitor whether flooding suppression
  is correctly configured on gateway interfaces. (PL-133202)

- kvm_host: fix fc-qemu-scrub timer which was not properly activating
  after boot. (PL-133211)

- Updated Nix to 2.3.18 to be able to download `zstd`-compressed paths from our Hydra. It will
  switch from `xz` to `zstd` to increase its throughput.

- Update nixpkgs from e8368806d2c792603b4c47afe0e3709a51d232a2 to ebcc9ab51d9d5495508eb5c520eb188aecd7f799
    - chrome, chromium: 130.0.6723.116 -> 131.0.6778.108 (CVE-2024-12053, CVE-2024-11395, CVE-2024-11110, CVE-2024-11111, CVE-2024-11112, CVE-2024-11113, CVE-2024-11114, CVE-2024-11115, CVE-2024-11116, CVE-2024-11117)
    - firefox: 132.0.2 -> 133.0 (CVE-2024-11691, CVE-2024-11692, CVE-2024-11701, CVE-2024-11694, CVE-2024-11695, CVE-2024-11696, CVE-2024-11697, CVE-2024-11704, CVE-2024-11698, CVE-2024-11705, CVE-2024-11706, CVE-2024-11708, CVE-2024-11699)
    - percona80: (CVE-2024-21171, CVE-2024-21177, CVE-2024-21163, CVE-2024-21173, CVE-2024-21179, CVE-2024-21127, CVE-2024-21129, CVE-2024-21125, CVE-2024-21130, CVE-2024-21162, CVE-2024-21165, CVE-2024-21142, CVE-2024-21134)
    - php81: 8.1.30 -> 8.1.31 (CVE-2024-8932, CVE-2024-8929, CVE-2024-11236, CVE-2024-11234, CVE-2024-11233, GHSA-4w77-75f9-2c8w)
    - php83: 8.3.13 -> 8.3.14 (CVE-2024-8932, CVE-2024-8929, CVE-2024-11236, CVE-2024-11234, CVE-2024-11233, GHSA-4w77-75f9-2c8w)
    - rclone: apply patch for CVE-2024-52522
    - zoneminder: 1.36.34 -> 1.36.35 (GHSA-rqxv-447h-g7jx)

# Release 2024_034

## Impact

- There is a small but non-zero potential that some clients may experience connectivity issues with nginx.
  Multiple connectivity testing tools showed no change for clients and/or libraries but cannot cover every single implementation out there.

- services using an updated package will be restarted

- Activate DDoS SSH rules in fail2ban for production machines.

## NixOS XX.XX platform

- agent: fix merging cold boot activities into warm reboots. We noticed maintenance requests that have been postponed multiple times on some machines, causing repeated maintenance notification mails. (PL-133180).

- Increase SSL validation check timeout to better distinguish DNS resolution
  errors and other causes of timeouts. (PL-133125)

- Restrict a class of key agreement protocols, called Diffie-Hellman Elliptic Curves, enabled in Nginx to mitigate a DoS attack vector
  described in CVE-2024-41996. The curves for ECDHE ciphers are then restricted to x25519, secp256r1, and x448.

- Update the mailserver role documentation with an example nix configuration

- Fix permissions for some platform logic that creates a `.erlang.cookie` for rabbitmq which would previously cause a failure when starting the service.
  The problem was caused due to insufficient write permissions when attempting to write the cookie after rabbitmq's first startup.
  During first startup, rabbimq generates a random cookie, writes it to the appropriate file and sets that file to be read-only.

- Pull upstream NixOS changes, security fixes and package updates (PL-133203):
    - chromium: 130.0.6723.69 -> 130.0.6723.116 (CVE-2024-10826, CVE-2024-10827, CVE-2024-10487, CVE-2024-10488)
    - element-web: 1.11.82 -> 1.11.85
    - firefox: 132.0 -> 132.0.2
    - ghostscript: 10.03.1 -> 10.04.0
    - git: 2.44.1 -> 2.44.2
    - github-runner: 2.320.0 -> 2.321.0
    - gitlab: 17.2.9 -> 17.3.7
    - go_1_22: 1.22.6 -> 1.22.8
    - go_1_22: 1.22.6 -> 1.22.8, (#345953)
    - grafana: 10.4.11 -> 10.4.12
    - imagemagick: 7.1.1-38 -> 7.1.1-39
    - libtiff: patch for CVE-2023-52356 & CVE-2024-7006
    - matrix-synapse: 1.118.0 -> 1.119.0
    - nodejs_18: 18.20.4 -> 18.20.5
    - nodejs_22: 22.8.0 -> 22.10.0, (#349157)
    - nspr: 4.35 -> 4.36
    - nss_latest: 3.105 -> 3.106
    - postgresql_12: 12.20 -> 12.21
    - postgresql_13: 13.16 -> 13.17
    - postgresql_14: 14.13 -> 14.14
    - postgresql_15: 15.8 -> 15.9
    - postgresql_16: 16.4 -> 16.5
    - python311: 3.11.9 -> 3.11.10
    - python312: 3.12.5 -> 3.12.6
    - redis: 7.2.4 -> 7.2.6 (CVE-2024-31449, CVE-2024-31227, CVE-2024-31228)
    - unzip: apply patch for CVE-2021-4217
    - vim: 9.1.0707 -> 9.1.0765 (CVE-2024-47814)

- Scheduled rotation of CS' root ssh key

- Activate DDoS SSH rules in fail2ban for all machines as protection against SSH DHeat attacks. (PL-132477)
  This may have impact if you have multiple unauthenticated SSH connections in a short time.
  We tested this change on non-production machines over the last 3 weeks and got no reports of problems.

- fc-luks: fix rekeying to use the specified encryption parameters. We accidentally fell back to defaults before. (PL-133174)

- router: the ISC DHCP server, which is end-of-life, has been replaced
  with its successor implementation, Kea. (PL-133205)

- pkgs: fix the monitoring script for the IPv4 underlay network to
  correctly handle next hop addresses sent by Nokia SR Linux
  switches. (PL-133199)

- router: fix radvd config generation to use the correct derived
  interface name. (PL-133201)

# Release 2024_033

## NixOS XX.XX platform

- physical machines: load `dm_mirror` kernel module by default, to support several LVM disk migration scenarios

- Update fc.qemu to ensure reduce cluster load on rbd list. (PL-133194)


# Release 2024_032

## NixOS XX.XX platform

- fc.qemu: fix bug that may cause accidental root disk shrinks after a
  cold reboot. (PL-133166)

# Release 2024_031

## Impact

- NFS clients will be rebooted to activate the new configuration. This happens
  as a side effect of a kernel update. In the future changes to NFS client
  settings will cause explicit reboot requests.

- Activate DDoS SSH rules in fail2ban for non-production machines

- Machines will schedule a maintenance reboot to activate the new kernel.

## NixOS XX.XX platform

- Implement automatic (offline) migration of VM disks between different pools
  (SSD <-> HDD). (PL-131857)

- Switch our central DNS recursive resolvers to prefer the default Quad9
  servers to alleviate reliability issues. We used to prefer the Quad9
  servers with improved geolocation capabilities, but experienced subtle
  DNS issues while using them and were advised by Quad9 to switch to the
  default servers. (PL-133125)

- Improve central DNS recursive resolver debugging capabilities. (PL-133125)

- Make NFS clients more resilient against missing servers during bootstrap,
  upgrades, and reboot scenarios. (PL-133062)

- Activate DDoS SSH rules in fail2ban for non-production machines. (PL-132477)
  This may have impact if you have multiple unauthenticated SSH connections in a short time.
  We will roll out this change to production VMs too if no problems occur.

- Explain how to use the the new release metadata URLs in DevHosts. (FC-41601)

- varnish: Fix syntax error handling during hot reloads. We silently did
  not fail on errors which masked issues until the next reboot causing
  varnish to then fail e.g. during scheduled maintenance. We now fail
  more visibly but keep running the old config, still. (FC-41403)

- Pull upstream NixOS changes, security fixes and package updates:
    - chromium: 129.0.6668.100 -> 130.0.6723.69 (CVE-2024-10229, CVE-2024-10230, CVE-2024-10231)
    - discourse: 3.2.5 -> 3.3.2
    - docker: 27.3.0 -> 27.3.1
    - element-web: 1.11.81 -> 1.11.82
    - firefox: 131.0.3 -> 132.0
    - github-runner: 2.319.1 -> 2.320.0
    - gitlab: 17.2.8 -> 17.3.6
    - grafana: 10.4.10 -> 10.4.11
    - linux: 5.15.164 -> 5.15.169
    - nss_latest: 3.105 -> 3.106
    - unifi8: 8.4.62 -> 8.5.6
