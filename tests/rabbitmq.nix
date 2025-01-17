import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:
let
  # Default IP automatically assigned in NixOS tests. Must not be changed here.
  ipv4 = "192.168.3.1";
  nodeDefaults = {
    flyingcircus.roles.rabbitmq.enable = true;

    flyingcircus.encServices = [
      {
        address = "machine.gocept.net";
        location = "test";
        password = "baz";
        service = "rabbitmq-node";
      }
    ];
  };

in {
  name = "rabbitmq";
  nodes = {
    machine = { ... }: {
      imports = [
        nodeDefaults
        (testlib.fcConfig {id = 1;})
      ];
    };
    multiNode =  { ... }: {
      imports = [
        nodeDefaults
        (testlib.fcConfig {id = 2;})
      ];
      flyingcircus.encServices = [
        {
          address = "multiNode.gocept.net";
          location = "test";
          password = "bar";
          service = "rabbitmq-node";
        }
      ];
    };
  };

  testScript = let
    cli = "sudo -u rabbitmq rabbitmqctl";
    amqpPortCheck = "nc -z ${ipv4} 5672";
    sensuOpts = "-u fc-sensu -w ${ipv4} -p ${testlib.derivePasswordForHost "sensu"}";
    amqpAliveCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-amqp-alive.rb ${sensuOpts}";
    nodeHealthCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb ${sensuOpts}";
  in ''
    start_all()
    machine.wait_for_unit("rabbitmq.service")
    machine.wait_until_succeeds("${amqpPortCheck}")

    print(machine.succeed("${cli} status"))

    # make sure this is run before continuing
    machine.succeed("systemctl start fc-rabbitmq-settings");

    with subtest("settings script must create monitoring users and set their monitoring tag"):
      machine.succeed("${cli} list_users | grep fc-telegraf | grep monitoring")


    with subtest("settings script must delete default guest user"):
      machine.fail("${cli} list_users | grep guest");

    with subtest("single-node cluster must auto-activate all feature flags"):
      machine.succeed("journalctl -g 'Enabling all feature flags'")
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

    multiNode.wait_for_unit("rabbitmq.service")

    with subtest("no auto-activation of feature flags on multi-node clusters"):
      multiNode.fail("journalctl -g 'Enabling all feature flags'")

  '';
})
