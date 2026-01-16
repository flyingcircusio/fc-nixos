<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

- restart of the postfix service due to configuration changes if the mailstub role is active

### NixOS XX.XX platform

- fix an issue with the Postfix configuration when using the mailstub service that would lead to an unintended hostname in SMTP HELO and EHLO commands
