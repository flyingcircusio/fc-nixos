<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### NixOS XX.XX platform

- `fc-luks keystore rekey` and `fc-luks volume unlock` with `--parallel`:
  render the progress bar on the same console the messages are printed to, so
  volume names, `cryptsetup` call echoes and errors no longer interleave into
  the progress bar rows (PL-135511)
