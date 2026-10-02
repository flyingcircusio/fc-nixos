### NixOS XX.XX platform

- The LUKS keystore volume now fits on a small key stick: it is formatted as ext4 and takes the whole volume group instead of a fixed 1g, and the stick is mounted by its `keys` label whichever filesystem it carries. (PL-135638)
