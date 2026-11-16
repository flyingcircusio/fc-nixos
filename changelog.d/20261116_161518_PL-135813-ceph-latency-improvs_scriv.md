<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- ceph: improvements to monitoring and gathered device metrics (PL-135813)
  - ceph daemons gather device health metrics
  - sensu-checks and the related alerting now considers existing health check mutes in the cluster
- ceph/fc-ceph: improvements for device latency (PL-135813)
  - enable discard/trim by default for Bluestore OSDs
  - zap partition table information of base PV when destroying/rebuilding volumes
  - support running `blkdiscard` on OSD base disks at creation or rebuild
