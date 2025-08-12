<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- Switch Ceph monitor connection config to IP addresses. (PL-133752)

  After a refactoring of our Ceph client library bindings, switching from
  C-based bindings to CLI calls we are now more prone to any DNS issues
  causing problems when instrumenting live migrations. We now connect to
  mons directly using their IP addresses which takes DNS out of the loop
  as a potential failure point.
