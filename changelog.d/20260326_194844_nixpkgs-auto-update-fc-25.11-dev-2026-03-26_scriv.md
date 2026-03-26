<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

<!-- Impact means "when this change is rolled out, there
     might be interruptions/downtimes/required actions/... that
     IMPACT THE RUNNING APPLICATION NEGATIVELY.

     Having new features or changed is not an "impact". That's what
     the main changelog (see below) is for.
     -->


- varnish-7.x is still default for the `webproxy` role but has known vulnerabilities. Consider updating to varnish-8.0 by setting `services.varnish.package = varnish80;`. Note the [breaking changes](https://vinyl-cache.org/docs/8.0/whats-new/upgrading-8.0.html) of that updated.
  - Vulnerability VSV00018 is already mitigated by additional config in our webproxy role.
  - Nonetheless, other upcoming security vulnerabilities will not be fixed for varnish-7.x.

### NixOS XX.XX platform

- provide `varnish80` package (PL-135243)
