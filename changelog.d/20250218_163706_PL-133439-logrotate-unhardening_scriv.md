<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->


### NixOS XX.XX platform

- Fix rotation of some service logs by relaxing logrotate service hardening (haproxy, mysql, ceph, …) [PL-133439]
    - The affected services might need to be restarted, but this will also happen as a side affect of the machine reboot scheduled by this release.
