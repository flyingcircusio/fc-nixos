{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-rabbitmq";
  exes = [ "check-rabbitmq-alive.rb" ];
}
