<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### NixOS XX.XX platform

- On most machines, agent units (fc-agent, fc-collect-garbage, fc-update-channel) now use
  a more dynamic throttling mechanism (cgroup's `io.weight`) so that
  the new burst mechanism and generally idle IOPS can be used without
  hurting application load. Under stress those units can consume at
  most 20% of all available IOPS.
  - Database VMs (mongodb, mysql, postgresql) are still using the previous, more strict throttling mechanism due to implementation challenges.
