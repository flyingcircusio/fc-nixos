(nixos-rabbitmq)=

# RabbitMQ

A managed instance of the [RabbitMQ](http://rabbitmq.com) message broker in the latest version provided by NixOS which is 3.12 at the moment.

## Configuration

The server listens for AMQP connections on the first IP of the *srv* interface on port 5672.

Additional configuration using the Erlang syntax can be placed in
{file}`/etc/local/rabbitmq/rabbitmq.config`.

We remove the guest user for security reasons.

## Interaction

Service users can access the rabbitmq account with {command}`sudo -iu rabbitmq`
to perform administrative tasks with {command}`rabbitmqctl`.

## Monitoring

The default monitoring setup checks that the RabbitMQ server is healthy and responding to AMQP connections.

## Feature Flags and Upgrading

RabbitMQ 3.8 introduced [Feature Flags](https://www.rabbitmq.com/feature-flags.html)
to allow rolling upgrades of clusters. Newer versions can require certain
feature flags to be enabled before upgrading or they will refuse to start.

After upgrading a cluster, enable all feature flags:

```shell
sudo -u rabbitmq rabbitmqctl enable_feature_flag all
```

## Upgrading from NixOS 20.09 while keeping RabbitMQ 3.6.5

To be able to upgrade NixOS 20.09 machines using the `rabbitmq36_5` role,
we provide a way to keep the unchanged rabbitmq service running after the system
upgrade. This conserves the specific rabbitmq config for the machine and
cannot be used on new 23.11 machines.

The upgrade process starts with generating Nix config on the running machine.
Put the generated config in :file:`/etc/local/nixos/rabbitmq365-frozen.nix`.

```shell
#!/usr/bin/env sh
service=$(realpath /etc/systemd/system/rabbitmq.service)
storePath=${service%%/rabbitmq.service}
cat <<EOF
# Generated config to freeze the existing rabbitmq unit file and all dependencies
# to keep it running after an upgrade to 23.11.
{ lib, ... }:
{
  # This no-op option declaration is needed for building the 20.09 system.
  options.flyingcircus.services.rabbitmq365Frozen.service = lib.mkOption {};

  # On 20.09, this setting changes nothing. It's only effective on 23.11.
  config.flyingcircus.services.rabbitmq365Frozen.service =
    builtins.storePath $storePath;
}
EOF
```

After that, change the VM environment to a 23.11 edition, keep the
`rabbitmq36_5` role enabled and rebuild. The `rabbitmq.service` will stay
active during the upgrade.

Changes to RabbitMQ's configuration via NixOS options or
`/etc/local/rabbitmq`. are not possible after the upgrade.


% vim: set spell spelllang=en:
