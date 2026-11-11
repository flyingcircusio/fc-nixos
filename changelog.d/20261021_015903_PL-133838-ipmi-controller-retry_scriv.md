### Impact


### NixOS XX.XX platform

- `configure-ipmi-controller.service` is retried by systemd with geometric
  backoff: `Restart=on-failure`, 5s up to 60s delay, at most six attempts, 30
  seconds timeout per attempt. A late-appearing IPMI device no longer leaves
  the unit failed until it is restarted manually. (PL-133838)
