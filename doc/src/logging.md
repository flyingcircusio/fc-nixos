(nixos-logging)=

# Logging

```{image} images/logging250.png
:class: logo
:width: 250px
```

Creating, storing, and analysing logs from components and your application is
an important part of keeping your service healthy and developing it further.

On the most basic level, our {ref}`managed components <nixos-components>`
log to the systemd journal or provide regular log files.
Log files are rotated by {ref}`nixos-logrotate` which can also be configured for
custom log files.
