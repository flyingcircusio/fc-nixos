(nixos-cron)=

# Cron

NixOS generally uses `systemd` which provides "Timers" as a replacement for
cron. However, for your convenience, regular cron is available on NixOS
machines.

:::{note}
User crontabs are not managed within the NixOS
configuration model: there is no versioning and no atomic loading.
Use systemd timers instead, if you can.
:::

## Installing user crontabs

You can edit a user's crontab with the regular {command}`crontab` command. See
{manpage}`crontab(1)` for details.

## Environment

Cron jobs are executed with a rather minimal environment. The default is
something like:

```sh
HOME=/home/user
LOGNAME=user
PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin
SHELL=/bin/sh
USER=user
```

Often, this set of environment variables is not sufficient. To get a full
environment similar to the one present in interactive sessions, prefix your
cronjob with `source /etc/profile;`, e.g.:

```
* * * * * source /etc/profile; complicated_command
```

There is also the possibility to set custom environment variables at the top of
a user crontab. See {manpage}`crontab(5)` for details.

We advise strongly to include a line like

```sh
MAILTO=mail@address
```

into the top section to get error mails delivered to an address where they are
actually read and acted upon.
