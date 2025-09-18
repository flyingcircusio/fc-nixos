# Release 2025_034


# Release 2025_032

## NixOS XX.XX platform

- devhost: remove insecure performance improvement options for PostgreSQL. (PL-133628)

  We saw multiple PostgreSQL instances not starting correctly after an unclean shutdown of
  the instance. In performance testing we saw a negligible benefit only.

  Note that this only affected customers on devhosts.



# Release 2025_026

## NixOS XX.XX platform

- On most machines, agent units (fc-agent, fc-collect-garbage, fc-update-channel) now use
  a more dynamic throttling mechanism (cgroup's `io.weight`) so that
  the new burst mechanism and generally idle IOPS can be used without
  hurting application load. Under stress those units can consume at
  most 20% of all available IOPS.
  - Database VMs (mongodb, mysql, postgresql) are still using the previous, more strict throttling mechanism due to implementation challenges.



# Release 2025_025

## NixOS XX.XX platform

- Improve IO throttling on our hypervisors:

  * HDD-class VMs can burst up to 2.500 IOPS for 60 seconds and
    have an explicit bandwidth limit of 250 MiB/s.
  * SSD-class VMs can burst up to 20.000 IOPS for 60 seconds
    and have an explicit bandwidth limit of 500 MiB/s.
  * Reads and writes are now throttled separately, so all VMs
    can use their IOPS limit separately for reading and
    writing at the same time.



# Release 2025_023

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- Improve convergence in internal S3 user management. Secrets are now also being reported back to our configuration
  management. This reduces error potential in the future in the secret management (PL-133656)

- Improve our internal image update script to not fail on temporary DNS errors (PL-133726)

- sudo: 1.9.17 -> 1.9.17p1 (CVE-2025-32462, CVE-2025-32463)



# Release 2025_021

## Impact

- Machines will reboot to activate the changed kernel.


## NixOS XX.XX platform

- Linux kernel: use 6.12.x LTS series as default stable kernel (PL-133760)

  Promote the 6.12.x LTS Linux kernel series as our default stable kernel.

  This seems to help resolve some recent IO latency / stalling issues

- Memory management: switch to smaller, fixed size dirty page buffers (PL-133760)

  This also seems to be a factor in the recent IO latency / stalling issues:
  The dirty page buffers were based on percentages of the installed RAM so far,
  but can cause long periods of stalling when the kernel passes the hard
  threshold to flush it.

  We now provide much smaller and fixed sizes for dirty pages (16 MiB to start
  flushing in the background and 64 MiB to enforce flushing).

- nix: fix GHSA-g948-229j-48j3

- agent: the command `fc-manage switch` now has a `-R` option which
  will activate the new configuration by performing an immediate
  reboot, similar to the process used for upgrading between major
  versions. (PL-133308)



# Release 2025_020


# Release 2025_019


# Release 2025_018

## Impact

- A bullet item for the Impact category.

-


## NixOS XX.XX platform

- Invalid NixOS `state_version` files are automatically fixed to fit the expected YY.MM format. (PL-133559)

- Add a new JSON-based log format to Nginx that is being used to ship access logs to a Loki instance automatically if one is present (PL-133702)



# Release 2025_017


# Release 2025_017

## Impact

- Telegraf will be restarted.

-

- The Redis cache of GitLab will be flushed.

- GitLab will be restarted.


## NixOS XX.XX platform

- Additional Redis servers configured with `services.redis.servers` now
  get Sensu checks and their metrics are scraped by Telegraf.

  This is not possible if a server doesn't have a TCP listener and its UNIX socket isn't
  readable & writable by its owning group. For each server like that, a warning
  will be printed.

- The option `services.telegraf.environmentVariablesFromFile` was introduced which allows
  substituting variables inside the Telegraf config with the content of a file.

- fix some configuration options for the loki role (PL-133581)

- Fix fs-check script by restoring old use of fc-directory cli (PL-133676)

- The GitLab role requires an active Redis role on the same machine.



# Release 2025_016

## Impact

-


## NixOS XX.XX platform

- gitlab: generate ActiveRecord encryption secrets

- agent: fix accidental immediate reboots on machines that use specialisations. (PL-133685)

- Removed a PHP test which checked for an issue that has been resolved for some time now (PL-133352)



# Release 2025_015

## Impact

- k3s: version 1.29 is end-of-life and should be considered insecure. Users are encouraged to upgrade their k3s cluster to a more recent version.

- Slurm services will be restarted.


## NixOS XX.XX platform

- varnish: Listen addresses are filtered by uniqueness. Before that, adding the same listen IP twice would break Varnish on startup.

- A bullet item for the NixOS XX.XX platform category. (FC-XXXX)

- The default Nix has been upgraded to 2.25.

- Slurm nodes will be returned to service after an unexpected reboot.



# Release 2025_014

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- nixos/default-packages: remove atop (PL-133575)
  atop has/had security problems and we see not much use.
  Remove in the default platform as it's still accessible with nix-shell.

- antivirus: fix listen statement on devhost setups (PL-133648)

- s3users: error when unknown error occurs (PL-133656)
  This is a safeguard against unexpected errors happen in the rgw user list
  / user info calls leading to a re-creation of the user with a new secret key.



# Release 2025_013

## NixOS XX.XX platform

- lamp: Fix evaluation error when a `php.ini` references a derivation (PL-133642).

- Activate configuration changes in an (immediate) boot cycle when upgrading (or downgrading)
  the NixOS major release. (PL-133570)

  We've experienced too many paper cuts, trying to get pure "online upgrades" working reliably
  in our fleet. Many edge cases like systemd upgrades, NFS connections, have shown that this
  isn't possible in the general case.

  As NixOS major releases ship with different kernel versions anyway and thus always scheduled
  to perform an immediate reboot in maintenance, we no defer the whole config update into
  that reboot.

  If a config change is applied manually and causes a major version change, the reboot will
  be applied immediately - after warning the user visually and giving a 10 second countdown
  in case of the user wanting to abort.

- nixos/kernel: update verification kernel 6.6 -> 6.12 (PL-133562)
  Kernel verision 6.12 is the new LTS. This change makes that version
  default on non-production hosts to try it out.

- Rotate zagy's root ssh key (PL-133335)



# Release 2025_012

## NixOS XX.XX platform

- Update fc-qemu to fix performance issue that caused a storage outage due to
  OSD hotspot behaviour. (PL-133632)

- Configure the sender domain for `mailutils` based programs to be the fully qualified hostname by default. (PL-133552)

- coturn: ensure that the coturn process can bind to port 443 when
  enabled by the Jitsi role. (PL-133419)

- Increase interval for scrubbing VMs. In large clusters this is becoming
  too expensive and since we introduced the per-VM supervisor this isn't
  as relevant any longer. (PL-133632)

- kvm: provide resolver services to layer 3 routed guest interfaces
  also on the subnet virtual router IPv6 address. (PL-133325)

- fc.qemu: multiple changes to improve the support for cloud-init-based VMs (Ubuntu) (PL-133325)

  - Provision IPv6 nameserver to support IPv6-only VMs

  - Upgrade packages on first boot.

  - Fix cloud-init instance ID handling to avoid regenerating SSH host keys too often.

  - Ensure network settings are updated on every boot.


## Impact

- A bullet item for the Impact category.

- A bullet item for the Impact category.



# Release 2025_011

## Impact

- DevHost VMs restart


## NixOS XX.XX platform

- devhost: Fix graceful shutdown of devhost VMs (PL-133536)

- router: add support for providing gateway services on layer 3 routed
  networks using VRFs. (PL-133324)

- kvm: support layer 3 routed networks when bootstrapping cloud-init
  VM's. (PL-133325)



# Release 2025_011


# Release 2025_011


# Release 2025_010


# Release 2025_010

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- nfs: fix platform network configuration to prevent machines with NFS
  mountpoints from hanging when switching to new system
  configurations. (PL-133570)

- Update our virtualisation tooling to Python 3.11 and remove C-level Ceph dependencies. (FC-133553)

- Add documentation for the statshost role, specifically on how to use it from a customer's perspective (PL-133028)



# Release 2025_009

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- docker: enable IP forwarding when the docker role is enabled, in
  order to allow containers to access external services. (PL-133589)

- Remove SSL Stapling from the default Nginx configuration since the default CA for NixOS provisioned certificates (Let's Encrypt) is ending OCSP support in 2025 (PL-133259)

- Make managing the IPMI admin username optional. Some machines do not support changing the name. (PL-133561)

- postgresql: pgvectorscale extension is now available as a package



# Release 2025_008

## NixOS XX.XX platform

- platform: ensure that IPv4 forwarding is properly disabled by
  default, and is only enabled by roles which explicitly require it
  (PL-133557).

- Add support Ubuntu VMs (and pave the way for general cloud-init based distributions) (PL-133325, PL-133372)

  Fetch users of all resource groups in qemu scrub to local filesystem.

  Fetch Ubuntu VM images from the `ubuntu` namespace in Ceph.

- Ensure the administrator username is always `ADMIN` and does not deviate
  depending on the vendor/integrator. (PL-133527)

- Add anti-spam DNS blocklist option with sensu checks and default to bl.spamcop.net. (PL-133519)

- rabbitmq: provide metrics from native prometheus exporter as well (PL-133391)
  - the existing metrics remain in place for now, this is in preparation for a later deprecation of `management_metrics_collection` in rabbitmq

- Improve test stability of our internal Qemu tooling. (PL-133300)



# Release 2025_007

## Impact

- A bullet item for the Impact category.

Devhost VMs get restarted

- A bullet item for the Impact category.

- [`rabbitmqadmin-ng`](https://www.rabbitmq.com/docs/management-cli) is now installed by default on machines with
  the `rabbitmq` role.


## NixOS XX.XX platform

- nginx, monitoring: also check validity of ACME (Letsencrypt) certificates
  that are not used for nginx HTTPS.
  There are two separate checks now: all ACME certs are checked via the local
  file system.
  Certificates used for nginx HTTPS get an additional check that works like the
  previous one, using HTTPS requests.
  We still assume here that nginx is listening for HTTPS on port 443.
  For special configurations, the sensu check command has to be overridden manually.

- devhost: stop VMs gracefully (PL-133536)

- percona83: bring back role to allow upgrading existing VMs from platform 24.05
  - percona-8.3.x is already end-of-life, we do not recommend adopting this role for new VMs
  - percona80 continues to be supported as a long-term support release thoughout the 24.11 platform version

- hardware: unload the XHCI USB driver at shutdown to work around a
  problem with certain kernel and hardware combinations improperly
  deconfiguring USB devices at shutdown (PL-133421).

- varnish: fix `varnish_http` sensu check execution, also check IPv6 bind addresses (PL-133554)

- issue trace messages when nixpkgs-21.05 is evaluated (PL-33522)
    - We still use parts of nixpkgs-21.05 for certain hardware and infrastructure features. As we generally do not expect it to be used in virtual machines though, emit a trace during evaluation to discover cases that differ.

- Monitoring for network interface speed: remove the limit for maximum speeds
  and make a more differentiated expectation around where we expect 1G or 10G+
  links. (PL-133472)

- devhost: improve error handling in image download (PL-133539)



# Release 2025_006

## NixOS XX.XX platform

- Add 24.11 to our physical installer and improve IPXE settings editor.

- matomo: improve cleanup of unwanted files after upgrading from matomo4 to matomo5 (PL-133012)

- install python-3.11 by default in addition to the default python-3.12

- fc-ipmitool: use `shell` as the default command.

- devhost: fix cleanup of old development VMs (PL-133467)

- Restart of `nix-daemon`.

- routers: fix traffic accounting with pmacctd by binding to correct interface again (PL-133497)

- Remove anti-spam DNS blacklist ix.dnsbl.manitu.net Manitu, which has been discontinued. (PL-133519)


## Impact

- Nix: downgrade production VMs to 2.18 (and upgrade the rest to 2.25).

  Due to a significant performance regression in 2.24, Nix will be rolled back
  to 2.18, the default from 24.05 and 23.11. Staging machines will get Nix 2.25
  as a preparation for upgrading the entire platform to 2.25.



# Release 2025_005

## Impact

-


## NixOS XX.XX platform

- internal: fix a regression in `restore-single-files` for accessing backups (PL-133416)
  - A behaviour change in `xfs_admin` resulted in a bug when adjusting filesystem UUIDs

- make fc-devhost operational on this platform version (PL-133416)

- Update backup software (backy and backy-extract). Mostly cosmetic changes
  and minor bug fixes.

- fc.agent.s3users: add timeouts, silence errors after user was deleted and add monitoring (PL-133447)

- Fix rotation of some service logs by relaxing logrotate service hardening (haproxy, mysql, ceph, …) [PL-133439]
    - The affected services might need to be restarted, but this will also happen as a side affect of the machine reboot scheduled by this release.

- lamp: For a phpfpm pool `name`, the executables `php-name` and `composer-name` are available in the VM.
  `php-name` calls the PHP interpreter that's also used by the phpfpm pool with the `php.ini` configuration
  of the phpfpm pool.

- percona: add configuration for alloy that exports slow logs to loki if configured for the resource group (PL-133028)



# Release 2025_004

## Impact

- Remove the postgresql12 role

- A bullet item for the Impact category.

- None.

- A bullet item for the Impact category.


## NixOS XX.XX platform

- pkgs, nixos: update frr to 8.5.7, and fix reload and restart
  behaviour to handle config changes and package upgrades correctly.

- Remove the postgresql12 role

- devhost: migrate dnsmasq extraConfig to structured settings (PL-133369)

- rabbitmq: add sensu check whether all feature-flags are enabled

- Internal: Prepare update-nixpkgs for new fc-release-tools versions

- router: fix reverse DNS zone generation to work with newer library
  version. (PL-132122)

- `fc-slurm check` does not crash anymore on hosts that are not a core slurm-node, but provides a helpful warning (PL-133153)

- Update nixpkgs from ba5c33f496bb04348a45e22ed4ef8c840e49fe29 to 3fc2232ff5841ed06df7d2cc2eb66a2c32e67cc6

- Set the `download-timeout` for Nix to 1 second.

- router: adapt and re-enable zebra integration in keepalived
  configuration. (PL-132122)

- Update nixpkgs from cd9c10b20341b57ab0ea1a757d1dd369b0065822 to ba5c33f496bb04348a45e22ed4ef8c840e49fe29

- platform: ensure that IPv6 autoconfiguration is correctly disabled
  on both physical and virtual hosts. (PL-133360)

- pulling in upstream package updates (TODO: put into upgrade docs)
  - postgres17: new package
  - imagemagick: now defaults to version 7, `imagemagick7` has been removed
  - mongodb_5_0: remove
  - linuxKernelVerify: just an alias to linux_latest for now



# Release 2025_002

## NixOS XX.XX platform

- Reorganize the dashboards that are provided for every customer with a statshost component in the Grafana UI into separate folders



# Release 2025_001

## NixOS XX.XX platform

- Changing a planned warm reboot to a cold reboot by merging does not trigger customer notifications and reschedule the maintenance window anymore. (PL-133301)

- Update nixpkgs from ff898be476375d3673334608f5a41efd9805258a to cc1f352acc315c2b36e5056055c026bfe3dd23cb

- matomo: continue to allow usage of matomo-4.x
  - The version is end-of-life now and has been marked as insecure by NixOS upstream. We continue to allow its usage during the 24.05 release cycle, but nonetheless recommend you to upgrade to matomo-5.x

- Internal: make gitlab NixOS test more stable

- Update nixpkgs from 28b740864b4e68f6a72bc35129d28ede5b273e62 to 9c9d7506c8f0883338ed9737dd8c886c64768ad2

- Rotate FL’ root ssh key as the old one was over 5 years old (FC-42115)

- Update nixpkgs from 81292057aadeb59b2d755a9a85e35e47492f4c2e to 28b740864b4e68f6a72bc35129d28ede5b273e62

- Update nixpkgs from ebcc9ab51d9d5495508eb5c520eb188aecd7f799 to ff898be476375d3673334608f5a41efd9805258a

- router: add new IPv6 ranges to the reverse DNS
  configuration. (PL-133322)


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
