<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### NixOS XX.XX platform

- nginx/webgateway: all TLS certificates are monitored for expiration now, by connecting to the HTTPS endpoint (check names `nginx_https_*`) and checking the certificate file directly: `ssl_cert_acme_*` (as before) or `ssl_cert_nginx_*` (added for non-ACME certs). Before, we only generated monitoring checks for ACME certs. (PL-134018)
