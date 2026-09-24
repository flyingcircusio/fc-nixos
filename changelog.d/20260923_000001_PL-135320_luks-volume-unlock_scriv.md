### NixOS XX.XX platform

- `fc-luks volume unlock <pattern>` unlocks matching LUKS volumes with the admin key, asking for the passphrase only once. This keeps a machine available when the local key stick fails and cannot be replaced immediately. (PL-135320)
