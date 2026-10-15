<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact


### NixOS XX.XX platform

- router: bind `atftpd` to the management address that DHCP advertises as
  `next-server`, so TFTP replies for PXE booting use the matching source
  address instead of an unrelated local one (PL-135554)
