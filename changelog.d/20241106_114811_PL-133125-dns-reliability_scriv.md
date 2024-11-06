<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- Switch our central DNS recursive resolvers to prefer the default Quad9
  servers to alleviate reliability issues. We used to prefer the Quad9
  servers with improved geolocation capabilities, but experienced subtle
  DNS issues while using them and were advised by Quad9 to switch to the
  default servers. (PL-133125)

- Improve central DNS recursive resolver debugging capabilities. (PL-133125)
