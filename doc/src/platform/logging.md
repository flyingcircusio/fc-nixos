# Logging { #nixos-logging }

![](images/logging250.png){ .logo }

Creating, storing, and analysing logs from components and your application is
an important part of keeping your service healthy and developing it further.

On the most basic level, our [managed components](../../platform-releases/fc-26.05-production/index.md#nixos-components)
log to the systemd journal or provide regular log files.
Log files are rotated by [nixos-logrotate](../../platform-releases/fc-26.05-production/logrotate.md#nixos-logrotate) which can also be configured for
custom log files.
