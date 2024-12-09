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

- Fix a bug in the reload script for the varnish service that only occurs when there are cold VCLs to be discarded. An error in the templating would lead to attempting to run a varnish admin instruction (vcl.discard in this case) as a shell command.
