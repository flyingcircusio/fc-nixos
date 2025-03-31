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

- Remove SSL Stapling from the default Nginx configuration since the default CA for NixOS provisioned certificates (Let's Encrypt) is ending OCSP support in 2025 (PL-133259)
