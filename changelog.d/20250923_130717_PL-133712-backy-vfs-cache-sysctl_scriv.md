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

- hardware: remove settings for aggressive filesystem caching which
  are no longer appropriate with widespread adoption of SSD-backed
  storage from the default hardware profile.

  Add a NixOS option `increaseVfsCacheWeight` in the backyserver role
  to allow enabling the previous behaviour on old HDD-based backup
  servers which may still benefit from increased caching. (PL-133712)
