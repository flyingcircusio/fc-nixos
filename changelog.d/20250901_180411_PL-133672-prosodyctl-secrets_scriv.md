<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- prosody.service will be restarted, potentially interrupting Jitsi sessions.


### NixOS XX.XX platform

- jitsi: fix interactive invocations of `prosodyctl` management command, it needs no access to the turncredentials_secret. (PL-133672)
