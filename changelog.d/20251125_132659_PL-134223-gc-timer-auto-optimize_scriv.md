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

- A bullet item for the Impact category.


### NixOS XX.XX platform

- userscan: multiple fixes

  * ignore missing files that may be encountered in race conditions (PL-132943)
  * correctly pick up user-owned exclude files from ~/.userscan-ignore (PL-133341)
  * extend global ignores: fc-nixos checkouts, lnav, appenv  (PL-134062)
