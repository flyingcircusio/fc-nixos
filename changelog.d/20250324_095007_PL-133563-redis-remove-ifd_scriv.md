<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- If you access `services.redis."".password` in your NixOS config, please change this to
  `flyingcircus.services.redis.password`.

### NixOS XX.XX platform

- redis: restructure internal password handling
  The password file /etc/local/redis/password now gets written as systemd ExecStartPre.
