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

- Added an option to provide a fallback configuration for the Varnish service that defaults to the contents of `/etc/local/varnish/default.vcl`.
  The configuration provided via this option will be applied if none of the virtual hosts' conditions defined via the NixOS configuration option
  `flyingcircus.services.varnish.virtualHosts.<name>` are matched or if none are defined. (FC-41407)
