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

- Fix systemd units managing flooding suppression and MAC learning
  configuration so that settings are restored to their defaults when
  the units are stopped. (PL-133202)

- Add sensu check on routers to monitor whether flooding suppression
  is correctly configured on gateway interfaces. (PL-133202)
