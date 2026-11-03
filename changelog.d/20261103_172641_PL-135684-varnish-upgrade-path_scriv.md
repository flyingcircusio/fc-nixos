<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

<!-- Impact means "when this change is rolled out, there
     might be interruptions/downtimes/required actions/... that
     IMPACT THE RUNNING APPLICATION NEGATIVELY.

     Having new features or changed is not an "impact". That's what
     the main changelog (see below) is for.
     -->


### NixOS XX.XX platform

- webproxy: simplify upgrade to fc-nixos-26.05 while keeping Varnish as package (PL-135684)

    As fc-nixos-26.05 [changes the underlying webproxy implementation to vinyl-cache](https://doc.flyingcircus.io/roles/fc-26.05-production/upgrade.html#nixos-upgrade-webproxy) by default, the config `flyingcircus.roles.webproxy.package = pkgs.varnish80` needs to be set to keep using varnish.
    This option is now already available on fc-nixos-25.11 and can be set ahead of the upgrade.
