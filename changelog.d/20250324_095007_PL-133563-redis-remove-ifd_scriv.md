<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

### NixOS XX.XX platform

- redis: restructure internal password handling
  The password file /etc/local/redis/password now gets written as systemd ExecStartPre. (PL-133653)

  If you set `services.redis."".requirePassFile` in your NixOS config, please use
  `flyingcircus.services.redis.password` instead. Also, reading the Redis password
  at evaluation time from `config.flyingcircus.services.redis.password` is not supported anymore.
