# Release 2024_035


## Impact

## NixOS XX.XX platform

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

# Release 2024_034


## Impact

## NixOS XX.XX platform

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

## NixOS XX.XX platform

- Implement automatic (offline) migration of VM disks between different pools
  (SSD <-> HDD). (PL-131857)

- Switch our central DNS recursive resolvers to prefer the default Quad9
  servers to alleviate reliability issues. We used to prefer the Quad9
  servers with improved geolocation capabilities, but experienced subtle
  DNS issues while using them and were advised by Quad9 to switch to the
  default servers. (PL-133125)

- Improve central DNS recursive resolver debugging capabilities. (PL-133125)
