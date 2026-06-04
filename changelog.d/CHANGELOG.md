# Release 2026_022


# Release 2026_019


# Release 2026_018

## NixOS XX.XX platform

- linux kernel: mitigate "dirty frag" vulnerabilities (CVE-2026-43500, CVE-2026-4328)



# Release 2026_017

## Impact

- Machines will reboot to enable a changed kernel.


## NixOS XX.XX platform

- linux kernel: fix copy.fail kernel vulnerability (CVE-2026-31431) (PL-135348)

- nix: fix privilege escalation (GHSA-vh5x-56v6-4368) (PL-135360)



# Release 2026_013

## NixOS XX.XX platform

- fix Nix security vulnerability CVE-2026-39860 / GHSA-g3g9-5vj6-r3gj (FC-52786)



# Release 2026_005

## Impact

- more packages are built locally in the VM

  Many packages cached before on cache.nixos.org cannot be pulled from there anymore, due cascading rebuilds caused by base package updates.
  All core roles and important packages are still pre-built by FlyingCircus, but VMs using less common packages might now need to build them locally. This can increase load on the machines **already ahead of the update**, when the update is prepared.


## NixOS XX.XX platform

- haproxy: switch default TLS backend to `openssl`, as `quictls` development is abandoned and has known vulnerabilities.

- grub: apply patches to make boots from XFS more resilient

- Improve logging and instrospection of kernel messages in early boot (PL-135139)



# Release 2026_001


# Release 2025_047

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- nixos/mail: correct dns.zone file with a non-default dkimSelector (PL-134262)

- devhost: start VMs only after network setup ran (PL-134208)

- installer: ignore failures when setting IPMI usernames



# Release 2025_046

## Impact

- k3s clusters with custom `clusterDNS`, `podCidr`, `serviceCidr` will fail to evaluate until adapted. See the change description below for details.

- A bullet item for the Impact category.


## NixOS XX.XX platform

- k3s clusters: options `clusterDns`, `podCidr`, `serviceCidr` are now a list

  affected roles: `k3s-agent`, `k3s-server`, `k3s-single-node`, `webgateway` when in a resource group with k3s nodes (PL-133889)

  The options `clusterDns`, `podCidr`, `serviceCidr` in the namespace `flyingcircus.kubernetes.network` have changed
  from option type *string* to a *list of strings*. This better reflects the ability to specify multiple IP
  address entries and process them at other parts of the configuration. \
  Deployments deviating from the default option value require manual adjustment of the option. The new system
  will fail to evaluate, preventing this release from bein installed automatically until the configuration
  value has been adjusted.

- ai-model-server: GPU monitoring amd_rocm_smi plugin: ensure all global tags are included but only include rocm specific tags that do not endanger label cardinality. Note: we include all fields, some are converted to tags but those are fine

- nixos/k3s: Fix resolving of cluster-internal hostnames in our frontend module (PL-134217)

- KVM hosts: fix a regression in maintenance handling (PL-134247)
  fc.qemu accidentally scrapped return codes set via sys.exit and replaced them with a 0, rendering maintenance guards ineffective. \
  Has been released as a hotfix to affected hosts ahead of schedule.



# Release 2025_044

## Impact

- A bullet item for the Impact category.

- A bullet item for the Impact category.

- Our AI service gateways will be restarted potentially being unreachable for a few seconds.


## NixOS XX.XX platform

- fc.qemu: fix a race condition between inner and outer shutdown (PL-134195)

- gitlab: fix false-positive nginx enableACME warning (PL-131381)

- nix: enable opportunistic nix store auto-optimisation (PL-134223)

  This is a preparatory step and will reduce storage needs for the
  nix store in the future with more aggressive changes coming up
  in the 25.11 release. Enabling opportunistic optimisation here
  will reduce the required effort to scan the store when upgrading.

- open-webui role: login flow redirects to correct host (FC-134218)

- Upgrade Ollama to the most current 0.12 release to support upgraded models.

- Upgrade our AI service gateway (skvaider) to improve logging, fix a few stability issues and increase monitoring depth. (PL-134061)



# Release 2025_043

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- Multiple bugfixes in fc.qemu for edge cases improving resiliency.

- Fix k3s firewall integration for IPv6 enabled k3s clusters. (PL-133889)



# Release 2025_042

## NixOS XX.XX platform

- statshost: fix Admin role mapping for OIDC. Note that OIDC is not enabled by default, yet, so instances with default configuration haven't been affected by this issue. (PL-134142)



# Release 2025_041

## Impact

- DevHost VMs can now have configurable disk sizes, allowing for larger development environments when needed.


## NixOS XX.XX platform

- DevHost: Added support for setting custom disk sizes for VMs via the `--disk-size` parameter and `disk-size` batou configuration option. VMs default to 25G if not specified. The filesystem automatically expands to use the full disk space on boot using existing fc-resize-disk functionality. (FC-48241)

- nixos/k3s: don't set cluster DNS in hosts resolv.conf (PL-134112)

  The hosts' resolv.conf is passed to the k3s cluster coredns, which leads
  to coredns trying to _sometimes_ resolve requests to itself.
  This leads to timeouts and otherwise failing DNS request.

  This change also modifies the behavior of DNS resolving on the host
  directly. Especially HAProxy now requires to especially set the CoreDNS
  as resolver. We checked that this won't affect customers currently.

- mailman: fix role throwing evaluation error on NixOS 25.05 (PL-133981)



# Release 2025_040

## NixOS XX.XX platform

- agent: fix several bugs related to invalid types (PL-133762)

- Update skvaider (our AI proxy) with improved logging. (PL-134061)



# Release 2025_039

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- nixos/mysql57: add deprecation warning if `mysql57` role is activated, as MySQL 5.7 is end-of-life for 2 years (PL-134105)

- fc.qemu: fix Ceph lock cleanups under some race conditions when shutting
  down VMs internally (FC-48755)

- nixos/mysql: Add new option bufferMemoryPercentage to allow adjusting mem usage (PL-133850)

  Currently, the memory percentage is fixed to 70%. This is too much when there is another service on the host.
  This option allows to customize this

- hardware: introduce a separate sensu check for the underlay network
  interfaces, to allow problems with these interfaces to be monitored
  and alerted upon separately. (PL-134114)

- hardware: fix networking for VMs with routed PUB interfaces. This
  was silently broken due to a previous fix for improving network
  stability. (PL-134136)

- hardware: monitor BGP sessions on underlay links, to allow detection
  of and alerting on conditions which would otherwise cause them to
  fail silently. (PL-133897)

- fc.qemu: add diagnostics for race condition on missing partition devices (PL-134011)

- fc.qemu: add retry logic for migration keepalive pings (PL-134121)

- Increase timeout for nix network connections from 1s to 5s. We used to run with a very low timeout
  to assist with automatic failovers for S3 reachability but are noticing that this
  is too twitchy in real world network scenarios too often and causes noise and alert fatigue.



# Release 2025_038


# Release 2025_038

## NixOS XX.XX platform

- fc-maintenance: fix detection whether a reboot is needed based on the kernel package (PL-134119)



# Release 2025_038

## NixOS XX.XX platform

- Improvements to machine maintenance management:

  1. Maintenances now automatically time out after the predicted
     time with some additional buffer. This reduces the risk of
     maintenances getting stuck without us noticing.

  2. Failed maintenances now communicate their stdout/stderr so that
     those can be quickly looked centrally and are noted in the relevant
     tickets for supporters to quickly diagnose.

  (PL-134087)

- fc-maintenance: fix detection whether a reboot is needed based on the kernel package (PL-134119)

# Release 2025_037

## NixOS XX.XX platform

- statshost-global: The Flying Circus infrastructure-wide statshost now stores metrics of the `nstat` telegraf output (PL-133683)

- fc-maintenance: detect need for reboot based on kernel package, not only version number (PL-134082)

  This makes the parsing of a system's used kernel more robust, and introduces reboots for changed kernels within the same version number.

- fc-agent: Fix automatic maintenance updates that referred to already garbage-collected system paths (PL-133993)

  This avoids breakage of updates even when they have been pending for a while and the current system state already changed, e.g. due to modified configuration.

- Increase DNS resolver timeouts. (PL-129951)

  We've seen sporadic but annoying DNS resolution issues which are likely
  caused by somewhat laggy DNS authoritatives or forwarders. One aspect
  of our previous combination of low timeouts and high retry count meant
  that clients a) might not be retrying correctly and b) resolvers might
  be retrying with different upstream servers that all exhibit the same
  sluggishness and thus then fail over and over and over.

  Increasing the timeouts will reduce fragility and reducing the number
  of retries means applications don't get stuck too long in case resolvers
  aren't responding

  Note: we're also adjusting our resolver setup in the next releases
  for further reliability improvements that integrate with this change.



# Release 2025_036

## Impact

- A bullet item for the Impact category.


## NixOS XX.XX platform

- loghost/graylog: Fix LDAP by pinning Java to a known good version. (PL-133980)

- hardware: remove settings for aggressive filesystem caching which
  are no longer appropriate with widespread adoption of SSD-backed
  storage from the default hardware profile.

  Add a NixOS option `increaseVfsCacheWeight` in the backyserver role
  to allow enabling the previous behaviour on old HDD-based backup
  servers which may still benefit from increased caching. (PL-133712)

- nixos/nginx: add deprecation warning for `virtualHosts.<name>.emailACME` as this option is deprecated and will be removed with fc-nixos 25.11 (PL-131381)

- nixos/statshost: Disable default insecure admin user (PL-134036)

  Currently, we have an insecure default admin activated, as this is the grafana default.
  With this change, this user is disabled on new installations and our AppOps team will disable the user on existing instances.

- nixos/nginx: Add warning for implicitly enabled `flyingcircus.services.nginx.virtualHosts.<name>.enableACME` as this behavior is deprecated and will be removed with fc-nixos 25.11 (PL-131381)



# Release 2025_035


# Release 2025_034

- Add new `ai-model-server` role for AI model inference capabilities using Ollama


## NixOS XX.XX platform

- Introduce ai-api-gateway role (PL-133948)

- Fix sensu check which reads the kernel message buffer to detect
  potentially broken XFS filesystems. (PL-133973)

- open-webui: add as new role that automatically integrates with the Flying Circus AI services.



# Release 2025_033

## NixOS XX.XX platform

- devhost: guest VM interfaces will now be correctly reattached to the
  bridge on the host if the host bridge interface is restarted.
  (PL-133436)

- Reduce size of fc-nixos release tarballs. Pinned old nixpkgs channels are only pulled in on-demand, not occupying space on most machines.



# Release 2025_032

## Impact

-

- prosody.service will be restarted, potentially interrupting Jitsi sessions.


## NixOS XX.XX platform

- Remove a misconfigured alias in the automatically generated Nginx configuration for the Grafana service that is enabled as part of the statshost role.
  This lead to plugins not loading for example due to a change in how Grafana routes to them interally. (PL-134006)

- devhost: remove insecure performance improvement options for PostgreSQL. (PL-133628)

  We saw multiple PostgreSQL instances not starting correctly after an unclean shutdown of
  the instance. In performance testing we saw a negligible benefit only.

  Note that this only affected customers on devhosts.

- jitsi: fix interactive invocations of `prosodyctl` management command, it needs no access to the turncredentials_secret. (PL-133672)



# Release 2025_031

## NixOS XX.XX platform

- Remove warning that file-based VCL configuration for varnish would be deprecated. (PL-133914)



# Release 2025_030

## Impact

-


## NixOS XX.XX platform

- Added a patch to libmodsecurity to fix a problem that caused nginx installations with modsecurity to segfault on reloads (PL-133894)

- Switch Ceph monitor connection config to IP addresses. (PL-133752)

  After a refactoring of our Ceph client library bindings, switching from
  C-based bindings to CLI calls we are now more prone to any DNS issues
  causing problems when instrumenting live migrations. We now connect to
  mons directly using their IP addresses which takes DNS out of the loop
  as a potential failure point.

- Kubernetes events are now shipped to both our custom monitoring platform as well as RG-specific loki instances to be used in grafana dashboards etc. (PL-133636)

- nginx: re-enable proxy buffering, but only in memory. (FC-47149)



# Release 2025_029


# Release 2025_028

## NixOS XX.XX platform

- k3s: Overriding the used package version `services.k3s.package` does not require an `mkForce` anymore.

- `fc-manage check` now displays all evaluation warnings of the system configuration, including package deprecations. (PL-133786)



# Release 2025_027

## Impact

- Restart of `coturn.service` & `prosody.service`.


## NixOS XX.XX platform

- The secret for the communication between `coturn` & `prosody` is no longer generated at eval-time (PL-133672).

  This fixes issues where the secret's store-path is garbage-collected and a new secret is enrolled
  on an agent run which lead to a subsequent restart of Jitsi mid-day in rare cases.



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

- devhost: switch to kea as dhcp server (PL-133857)

  We had seen issues with DHCP packets having an invalid checksum. Kea handles this better and seems to resolve provisioning issues.
  We continue to monitor the issues.

- postgresql: add role `postgresql17` for newest major release. All existing versions of the postgresql role remain available.

- Make XFS upgrades at boot-time optional and disable it by default.  (PL-133864)

  We introduced the XFS upgrade code in the 25.05 cycle to allow long-living
  filesystems enable features like "bigtime" which makes the filesystem
  year 2038 compatible. The implementation chose robustness over performance
  but the tradeoff ended up with boot times of tens of minutes even for
  small or medium VMs. We're taking this feature back to the drawing board,
  but provide a knob so it can be used in situations where it's really needed.



# Release 2025_024

## Impact

- A bullet item for the Impact category.

- A bullet item for the Impact category.


## NixOS XX.XX platform

- loghost: fix Graylog LDAP login which has been broken since 24.11. Graylog is deprecated, the role is only provided to upgrade existing loghosts (PL-133759).

- telegraf: enable [`nstat`](https://github.com/influxdata/telegraf/tree/master/plugins/inputs/nstat) input to provide network protocol stats

  In preparation of the [`net`](https://github.com/influxdata/telegraf/blob/2933b85c7dcdd816cc09584c7fca04ca7dfd55b2/plugins/inputs/net/README.md) input deprecating
  the report of network protocol metrics, this provides a transitory period of both legacy and future metrics being available.  \
  Deprecated metrics will be disabled in the next major Flying Circus 25.11 platform release.

- statshost: now supports OpenID Connect login for Grafana, using our Keycloak instance. Disabled by default for now, OIDC will replace LDAP login in the near future. (PL-133429)



# Release 2025_023


# Release 2025_022

## Impact

- Telegraf will be restarted.

-

- A bullet item for the Impact category.

-

- A bullet item for the Impact category.

- The Redis cache of GitLab will be flushed.

- GitLab will be restarted.

- gitlab: postgresql>=16 is required, please upgrade your postgres role before updating

- A bullet item for the Impact category.

-


## NixOS XX.XX platform

- Improve convergence in internal S3 user management. Secrets are now also being reported back to our configuration
  management. This reduces error potential in the future in the secret management (PL-133656)

- gitlab: fix registry port. (PL-133568)

- Additional Redis servers configured with `services.redis.servers` now
  get Sensu checks and their metrics are scraped by Telegraf.

  This is not possible if a server doesn't have a TCP listener and its UNIX socket isn't
  readable & writable by its owning group. For each server like that, a warning
  will be printed.

- The option `services.telegraf.environmentVariablesFromFile` was introduced which allows
  substituting variables inside the Telegraf config with the content of a file.

- Fix an issue with the alloy service being assigned a nonexistent role when nginx is not enabled. (PL-133737)

- redis: restructure internal password handling
  The password file /etc/local/redis/password now gets written as systemd ExecStartPre. (PL-133653)

  If you set `services.redis."".requirePassFile` in your NixOS config, please use
  `flyingcircus.services.redis.password` instead. Also, reading the Redis password
  at evaluation time from `config.flyingcircus.services.redis.password` is not supported anymore.

- k3s: The default package has been updated to k3s-1.32

- Introduced option `flyingcircus.permittedInsecurePackages` to allow additional packages marked as insecure.

- Improved error message when trying to use a package marked as insecure or unfree showing FCIO-specific instructions.

- When importing the platform channel (`import <fc> …`), declarations of `config.allowUnfreePredicate` and
  `config.permittedInsecurePackages` don't get discarded silently. In case of `allowUnfreePredicate`, at least
  one of the platform-provided or user-supplied predicate must evaluate to `true` to allow the instantiation of
  an unfree package.

- fix some configuration options for the loki role (PL-133581)

- Automatically build a list of all options and packages for consumption by the option/package search (PL-133663)

- pkgs.nodejs is updated from version 20 to 22

- Improve our internal image update script to not fail on temporary DNS errors (PL-133726)

- Small update of documentation strings on which type of configuration files
  are used for generated haproxy.cfg (PL-133666)

- Fix fs-check script by restoring old use of fc-directory cli (PL-133676)

- nix: use nix-2.25 on all machines

- dstat: drop as it is unmaintained, replace with `dool`
  - `dstat` is now an alias for `dool`

- latencytop: drop package, remove from default installation

- docker: fix role not working on devhosts (PL-133607)

  This change also prepares the role to work on machines without FE interface or PUB interface.

- The GitLab role requires an active Redis role on the same machine.

- Invalid NixOS `state_version` files are automatically fixed to fit the expected YY.MM format. (PL-133559)

- Fix a part of the alloy configuration that receives syslog messages from nginx (PL-133746)

- Add a new JSON-based log format to Nginx that is being used to ship access logs to a Loki instance automatically if one is present (PL-133702)

- Add a mechanism to upgrade XFS flags over time. Initially this will cause
  `bigtime`, `inobtcount` and `nrext64` flags to be set. With `bigtime` set VMs
  from this release on will consistently support file times beyond 2038, even if
  they were bootstrapped on older releases. (PL-133321, PL-130365)

- Prepare VMs to read ENC data (the config management metadata) seeded from the
  host from the separate `cidata` volume in the future. This allows disabling or
  reconfiguring /tmp to use tmpfs without breaking our configuration management.
  (PL-133311)

- agent: the command `fc-manage switch` now has a `-R` option which
  will activate the new configuration by performing an immediate
  reboot, similar to the process used for upgrading between major
  versions. (PL-133308)



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
