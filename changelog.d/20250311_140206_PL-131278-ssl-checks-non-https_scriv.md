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

- nginx, monitoring: also check validity of ACME (Letsencrypt) certificates
  that are not used for nginx HTTPS.
  There are two separate checks now: all ACME certs are checked via the local
  file system.
  Certificates used for nginx HTTPS get an additional check that works like the
  previous one, using HTTPS requests.
  We still assume here that nginx is listening for HTTPS on port 443.
  For special configurations, the sensu check command has to be overridden manually.
