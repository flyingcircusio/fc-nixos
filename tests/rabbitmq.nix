import ./make-test.nix ({ rolename ? "rabbitmq38", lib, pkgs, testlib, ... }:
let
  ipv4 = "192.168.101.1";
  amqpPortCheck = "nc -z ${ipv4} 5672";
  sensuOpts = "-u fc-sensu -w ${ipv4} -p ${testlib.derivePasswordForHost "sensu"}";
  amqpAliveCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-amqp-alive.rb ${sensuOpts}";
  nodeHealthCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb ${sensuOpts}";

in {
  name = "rabbitmq";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.${rolename}.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
          };
          gateways = {};
        };
      };
    };

  testScript = ''
    my $cli = 'sudo -u rabbitmq rabbitmqctl';
    $machine->waitForUnit("rabbitmq.service");
    $machine->waitUntilSucceeds("${amqpPortCheck}");

    print($machine->succeed("$cli status"));
    $machine->succeed("$cli node_health_check");

    # make sure this is run before continuing
    $machine->succeed("systemctl start fc-rabbitmq-settings");

    # settings script must create monitoring users and set their monitoring tag
    $machine->succeed("$cli list_users | grep fc-telegraf | grep monitoring");
    $machine->succeed("$cli list_users | grep fc-sensu | grep monitoring");

    # settings script must delete default guest user
    $machine->mustFail("$cli list_users | grep guest");

    # sensu checks should be green
    $machine->succeed("${amqpAliveCheck}");
    $machine->succeed("${nodeHealthCheck}");

    $machine->stopJob("rabbitmq.service");
    $machine->waitUntilFails("${amqpPortCheck}");

    # sensu checks should be red when service has stopped
    $machine->mustFail("${amqpAliveCheck}");
    $machine->mustFail("${nodeHealthCheck}");

    # service user should be able to write to local config dir
    $machine->succeed('sudo -u rabbitmq touch /etc/local/rabbitmq/rabbitmq.config');
  '';
})
