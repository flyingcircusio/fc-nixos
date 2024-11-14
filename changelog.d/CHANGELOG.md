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
