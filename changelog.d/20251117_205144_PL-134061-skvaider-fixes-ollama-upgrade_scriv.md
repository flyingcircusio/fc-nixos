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

- Our AI service gateways will be restarted potentially being unreachable for a few seconds.


### NixOS XX.XX platform

- Upgrade Ollama to the most current 0.12 release to support upgraded models.

- Upgrade our AI service gateway (skvaider) to improve logging, fix a few stability issues and increase monitoring depth. (PL-134061)
