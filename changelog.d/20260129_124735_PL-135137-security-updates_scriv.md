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

- more packages are built locally in the VM

  Many packages cached before on cache.nixos.org cannot be pulled from there anymore, due cascading rebuilds caused by base package updates.
  All core roles and important packages are still pre-built by FlyingCircus, but VMs using less common packages might now need to build them locally. This can increase load on the machines **already ahead of the update**, when the update is prepared.

### NixOS XX.XX platform

- haproxy: switch default TLS backend to `openssl`, as `quictls` development is abandoned and has known vulnerabilities.
