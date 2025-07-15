<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- Improve IO throttling on our hypervisors:

  * HDD-class VMs can burst up to 2.500 IOPS for 60 seconds and
    have an explicit bandwidth limit of 250 MiB/s.
  * SSD-class VMs can burst up to 20.000 IOPS for 60 seconds
    and have an explicit bandwidth limit of 500 MiB/s.
  * Reads and writes are now throttled separately, so all VMs
    can use their IOPS limit separately for reading and
    writing at the same time.

- Agent units (fc-agent, fc-collect-garbage, fc-update-channel) now use
  a more dynamic throttling mechanism (cgroup's `io.weight`) so that
  the new burst mechanism and generally idle IOPS can be used without
  hurting application load. Under stress those units can consume at
  most 20% of all available IOPS.
