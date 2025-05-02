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

- s3users: error when unknown error occurs (PL-133656)
  This is a safeguard against unexpected errors happen in the rgw user list
  / user info calls leading to a re-creation of the user with a new secret key.
