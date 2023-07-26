(nixos-rabbitmq)=

# RabbitMQ

A managed instance of the [RabbitMQ](http://rabbitmq.com) message broker at version 3.8.

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

% vim: set spell spelllang=en:
