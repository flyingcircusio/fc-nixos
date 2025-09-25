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

- statshost/grafana: users now authenticate using OIDC via Keycloak instead of LDAP, resulting in the same permissions as before. Logged-in users will still be shown as using LDAP. Users will be redirected to the FCIO Keycloak server by default when visiting the Grafana frontend. Logging in via OIDC will convert their user accounts automatically. LDAP can still be enabled by local config. When OIDC is enabled, local login is disabled completely. (PL-134048)
