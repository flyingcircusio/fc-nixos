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

- webgateway: TLS- or ACME-enabled vhosts that do not define a single valid hostname do not receive an automatic certificate check anymore (PL-135244)

  An evaluation warning informs about that behaviour change. The warning will be removed after 2 releases.


### NixOS XX.XX platform

- webgateway: Only generate certificate checks for vhosts defining a single valid hostname (PL-135244)
- `flyingcircus.services.sensu-client.checks`: Prevent illegal check names that would crash the client service (PL-135244)
- `flyingcircus.services.sensu-client.checks.enable`: introduce new option to explicitly disable checks
