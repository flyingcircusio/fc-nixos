<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- DevHost VMs can now have configurable disk sizes, allowing for larger development environments when needed.


### NixOS XX.XX platform

- DevHost: Added support for setting custom disk sizes for VMs via the `--disk-size` parameter and `disk-size` batou configuration option. VMs default to 25G if not specified. The filesystem automatically expands to use the full disk space on boot using existing fc-resize-disk functionality. (FC-48241)
