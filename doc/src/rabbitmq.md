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

% vim: set spell spelllang=en:
