<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- A bullet item for the Impact category.


### NixOS XX.XX platform

- fc-collect-garbage: fix user-specific ignore files (located in ~/.userscan-ignore).
  They have been ineffective for a longer time as non-root ignore files were never
  read by fc-userscan because of an issue with switching to the non-privileged user. (PL-133341)
