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
  The password file /etc/local/redis/password now gets written as systemd ExecStartPre. (PL-133653)

- telegraf: Add new option `environmentVariablesFromFile` that allows users to store
  passwords in files and using them as substituted environment variable in a telegraf input. (PL-133563)
