<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

-

### NixOS XX.XX platform

- Remove a misconfigured alias in the automatically generated Nginx configuration for the Grafana service that is enabled as part of the statshost role.
  This lead to plugins not loading for example due to a change in how Grafana routes to them interally. (PL-134006)
