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

- Optimize system updates in maintenance for reduced noise and robustness. (FC-57632)

  1. If no reboot was scheduled for a system updated but switching to the
     new config online fails for any reason, we immediately schedule a reboot
     with the new configuration to avoid leaving machines stuck in undefined
     states.

  2. We try harder to avoid superfluous online unit restarts if system updates
     have already scheduled.

  3. We ensure to extend the scheduled maintenance period if we initiate
     a reboot to avoid accidentally causing noisy keepalive alarms even
     though the system knows what it's doing right now.
