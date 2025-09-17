<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->



### NixOS XX.XX platform

- fc-agent: Fix automatic maintenance updates that referred to already garbage-collected system paths (PL-133993)

  This avoids breakage of updates even when they have been pending for a while and the current system state already changed, e.g. due to modified configuration.
