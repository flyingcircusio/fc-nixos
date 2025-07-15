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

- devhost: switch to kea as dhcp server (PL-133857)

  We had seen issues with DHCP packets having an invalid checksum. Kea handles this better and seems to resolve provisioning issues.
  We continue to monitor the issues.
