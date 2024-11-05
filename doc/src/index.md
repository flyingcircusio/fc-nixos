(nixos-platform-index)=
# Flying Circus platform {{ version }}

This is the documentation of the Flying Circus platform based on [NixOS]
{{ version }}.

It contains general information about our platform as well as individual
software components (roles).

## General platform

```{toctree}
:titlesonly: true

upgrade
maintenance
base
user_profile
local
systemd
cron
logging
logrotate
firewall
monitoring
fc_collect_garbage_userscan
```

(nixos-components)=

## Specific software components (roles)

```{toctree}
:titlesonly: true

devhost
docker
external_net
ferretdb
kubernetes
lamp
mailserver
mailstub
matomo
memcached
mongodb
mysql
nfs
opensearch
postgresql
rabbitmq
redis
slurm
statshost
webgateway
webproxy
```

[nixos]: https://nixos.org
