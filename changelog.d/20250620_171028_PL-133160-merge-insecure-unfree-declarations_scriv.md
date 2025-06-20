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

- Introduced option `flyingcircus.permittedInsecurePackages` to allow additional packages marked as insecure.

- Improved error message when trying to use a package marked as insecure or unfree showing FCIO-specific instructions.

- When importing the platform channel (`import <fc> …`), declarations of `config.allowUnfreePredicate` and
  `config.permittedInsecurePackages` don't get discarded silently. In case of `allowUnfreePredicate`, at least
  one of the platform-provided or user-supplied predicate must evaluate to `true` to allow the instantiation of
  an unfree package.
