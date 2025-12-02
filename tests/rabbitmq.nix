import ./make-test-python.nix (
  {
    lib,
    pkgs,
    testlib,
    ...
  }:
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

  in
  {
    name = "rabbitmq";
    nodes = {
      machine =
        { ... }:
        {
          imports = [
            nodeDefaults
            (testlib.fcConfig { id = 1; })
          ];
          services.telegraf.enable = lib.mkForce true;
        };
      multiNode =
        { ... }:
        {
          imports = [
            nodeDefaults
            (testlib.fcConfig { id = 2; })
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

    testScript =
      { nodes, ... }:
      let
        cli = "sudo -u rabbitmq rabbitmqctl";
        amqpPortCheck = "nc -z ${ipv4} 5672";
        sensuOpts = "-u fc-sensu -w ${ipv4} -p ${testlib.derivePasswordForHost "sensu"}";
        amqpAliveCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-amqp-alive.rb ${sensuOpts}";
        nodeHealthCheck = "${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb ${sensuOpts}";
        featureFlagCheck = testlib.sensuCheckCmd nodes.machine "rabbitmq-feature-flags-enabled";
        rabbitmqExporterPort = nodes.machine.flyingcircus.services.rabbitmq.prometheusPort;
        globalPrometheusPort = 9126; # port is hard-coded in nixos/platform/monitoring.nix
        # XXX srv address not added to /etc/hosts (PL-134248)
        machineGlobalPrometheusAddr = "http://${builtins.head nodes.machine.fclib.network.srv.v4.addresses}:${toString globalPrometheusPort}/metrics";
      in
      ''
        start_all()
        machine.wait_for_unit("rabbitmq.service")
        machine.wait_until_succeeds("${amqpPortCheck}")

        print(machine.succeed("${cli} status"))

        # make sure this is run before continuing
        machine.succeed("systemctl start fc-rabbitmq-settings");

        with subtest("settings script must create monitoring users and set their monitoring tag"):
          machine.succeed("${cli} list_users | grep fc-sensu | grep monitoring")


        with subtest("settings script must delete default guest user"):
          machine.fail("${cli} list_users | grep guest");

        with subtest("metrics exported via prometheus exporter and re-exported by telegraf"):
          machine.wait_until_succeeds("${lib.getExe pkgs.curl} ${machineGlobalPrometheusAddr} | grep 'rabbitmq_' | grep ':${toString rabbitmqExporterPort}'", timeout=30)

        with subtest("single-node cluster must auto-activate all feature flags"):
          machine.succeed("journalctl -g 'Enabling all feature flags'")
        with subtest("sensu checks should be green"):
          machine.succeed("${amqpAliveCheck}")
          machine.succeed("${featureFlagCheck}")
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
  }
)
