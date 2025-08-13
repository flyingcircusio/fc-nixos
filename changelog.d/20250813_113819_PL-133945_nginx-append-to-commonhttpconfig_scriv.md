<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- The Nginx worker processes will be restarted while applying this change due to changes to it's configuration. Since nginx can handle this using a hot reload, we expect no effective down-time.


### NixOS XX.XX platform

- Adjust the nginx configuration by moving general configuration like log formats up above the server configuration blocks (PL-133945)
