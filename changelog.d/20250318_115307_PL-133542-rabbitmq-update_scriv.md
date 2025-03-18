<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- rabbitmq users: When running multiple VMs with the `rabbitmq` role in the same RG, [feature flags need to be enabled manually](https://doc.flyingcircus.io/roles/fc-24.05-production/rabbitmq.html#feature-flags-and-upgrading) after the upgrade to prepare for later updates.

### NixOS XX.XX platform

- rabbitmq-server: 3.12.13 -> 3.13.7
  - necessary preparation for the update to rabbitmq-server 4.x in NixOS 24.11
