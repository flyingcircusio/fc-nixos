<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- Nix: downgrade production VMs to 2.18 (and upgrade the rest to 2.25).

  Due to a significant performance regression in 2.24, Nix will be rolled back
  to 2.18, the default from 24.05 and 23.11. Staging machines will get Nix 2.25
  as a preparation for upgrading the entire platform to 2.25.

### NixOS XX.XX platform

- Restart of `nix-daemon`.
