### Impact


### NixOS XX.XX platform

- AI model servers with the `skvaider-inference` service now register a
  maintenance hook: before a reboot or platform update, the inference server
  asks the proxy to move its models to another model server and waits until
  they are unloaded. If the models cannot be moved (not enough free capacity
  elsewhere), the maintenance is postponed instead of rebooting into an
  outage. (PL-135777)
