import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  # Default IP automatically assigned in NixOS tests. Must not be changed here.
  ipv4 = "192.168.1.1";

in {
  name = "rabbitmq";
  machine =
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.rabbitmq.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.1.0/24" = [ ipv4 ];
          };
          gateways = {};
        };
      };
      virtualisation.diskSize = 1000;
    };

  testScript = let
    cli = "sudo -u rabbitmq rabbitmqctl";
    amqpPortCheck = "nc -z ${ipv4} 5672";
    sensuOpts = "-u fc-sensu -w ${ipv4} -p ${testlib.derivePasswordForHost "sensu"}";
    amqpAliveCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-amqp-alive.rb ${sensuOpts}";
    nodeHealthCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb ${sensuOpts}";
  in ''
    machine.wait_for_unit("rabbitmq.service")
    machine.wait_until_succeeds("${amqpPortCheck}")

    print(machine.succeed("${cli} status"))

    # make sure this is run before continuing
    machine.succeed("systemctl start fc-rabbitmq-settings");

    with subtest("settings script must create monitoring users and set their monitoring tag"):
      machine.succeed("${cli} list_users | grep fc-telegraf | grep monitoring")
      machine.succeed("${cli} list_users | grep fc-sensu | grep monitoring")

    with subtest("settings script must delete default guest user"):
      machine.fail("${cli} list_users | grep guest");

    with subtest("sensu checks should be green"):
      machine.succeed("${amqpAliveCheck}")
      machine.wait_until_succeeds("${nodeHealthCheck}")
      machine.systemctl("stop rabbitmq.service")
      machine.wait_until_fails("${amqpPortCheck}")

    with subtest("sensu checks should be red when service has stopped"):
      machine.fail("${amqpAliveCheck}")
      machine.fail("${nodeHealthCheck}")

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u rabbitmq touch /etc/local/rabbitmq/rabbitmq.config')
  '';
})
