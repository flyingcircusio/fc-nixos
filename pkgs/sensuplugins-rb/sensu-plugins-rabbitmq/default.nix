{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-rabbitmq";
  exes = [
    "check-rabbitmq-alive.rb"
    "check-rabbitmq-amqp-alive.rb"
    "check-rabbitmq-node-health.rb"
    "check-rabbitmq-messages.rb"
  ];
}
