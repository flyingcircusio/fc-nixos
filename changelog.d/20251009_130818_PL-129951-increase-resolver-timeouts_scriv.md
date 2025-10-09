<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### NixOS XX.XX platform

- Increase DNS resolver timeouts. (PL-129951)

  We've seen sporadic but annoying DNS resolution issues which are likely
  caused by somewhat laggy DNS authoritatives or forwarders. One aspect
  of our previous combination of low timeouts and high retry count meant
  that clients a) might not be retrying correctly and b) resolvers might
  be retrying with different upstream servers that all exhibit the same
  sluggishness and thus then fail over and over and over.

  Increasing the timeouts will reduce fragility and reducing the number
  of retries means applications don't get stuck too long in case resolvers
  aren't responding

  Note: we're also adjusting our resolver setup in the next releases
  for further reliability improvements that integrate with this change.
