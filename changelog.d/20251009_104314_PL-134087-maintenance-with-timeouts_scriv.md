<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- Improvements to machine maintenance management:

  1. Maintenances now automatically time out after the predicted
     time with some additional buffer. This reduces the risk of
     maintenances getting stuck without us noticing.

  2. Failed maintenances now communicate their stdout/stderr so that
     those can be quickly looked centrally and are noted in the relevant
     tickets for supporters to quickly diagnose.

  (PL-134087)
