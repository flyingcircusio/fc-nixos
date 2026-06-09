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


### NixOS XX.XX platform

- fc-maintenance: stop execution of maintenance enter hooks at failure of individual hook (PL-135499)

  This resolves a possible race condition of multiple Ceph radosgw nodes being shut down in parallel.
