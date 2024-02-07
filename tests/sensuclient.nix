import ./make-test-python.nix ({ pkgs, lib, testlib, ... }:
let

  ipv4 = testlib.fcIP.srv4 1;
  ipv6 = testlib.fcIP.srv6 1;

  encServices = [
    {
      address = "machine.gocept.net";
      location = "test";
      password = "uiae";
      service = "sensuserver-server";
    }
    {
      address = "machine.gocept.net";
      location = "test";
      password = "uiae";
      service = "sensuserver-api";
    }
  ];

in
{
  name = "sensuclient";
  machine =
    { pkgs, config, ... }:
    {
      imports = [
        (testlib.fcConfig { net.fe = false; })
      ];
      flyingcircus.encServices = encServices;
      networking.domain = "gocept.net";
      flyingcircus.services.sensu-client.enable = true;
      flyingcircus.services.rabbitmq.enable = true;
      flyingcircus.services.rabbitmq.listenAddress = lib.mkOverride 90 "::";
      systemd.services.prepare-rabbitmq-for-sensu = {
        description = "Prepare rabbitmq for sensu-server.";
        partOf = [ "rabbitmq.service" ];
        wantedBy = [ "rabbitmq.service" ];
        after = [ "rabbitmq.service" ];
        path = [ config.services.rabbitmq.package ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "true";
          Restart = "on-failure";
          User = "rabbitmq";
          Group = "rabbitmq";
        };
        script =
          let
            # Taken from 21.05 sensuserver, reduced to a single client
            node = "machine.gocept.net";
            password = "uiae";
            name = builtins.head (lib.splitString "." node);
            permissions = [
              "((?!keepalives|results).)*"
              "^(keepalives|results|${name}.*)$"
              "((?!keepalives|results).)*"
            ];
          in
          ''
            rabbitmqctl add_user sensu-server asdf
            rabbitmqctl add_vhost /sensu
            rabbitmqctl set_user_tags sensu-server administrator
            rabbitmqctl set_permissions -p /sensu sensu-server ".*" ".*" ".*"

            # Configure user and permissions for ${node}:
            rabbitmqctl list_users | grep ^${node} || \
              rabbitmqctl add_user ${node} ${password}

            rabbitmqctl change_password ${node} ${password}
            rabbitmqctl set_permissions -p /sensu ${node} ${lib.concatMapStringsSep " " (p: "'${p}'") permissions}
          '';
      };
    };

  testScript = ''
    import json
    machine.wait_for_unit("rabbitmq.service")
    machine.wait_for_unit("prepare-rabbitmq-for-sensu.service")
    machine.wait_for_unit("sensu-client.service")
    machine.wait_for_open_port(3031)

    with subtest("sensu client should respond to HTTP"):
      out = machine.succeed("curl localhost:3031/brew")
      assert {"response":"I'm a teapot!"} == json.loads(out)

    with subtest("sensu client config should have basic checks configured"):
      out = machine.succeed("sensu-client-show-config")
      config = json.loads(out)
      assert "disk" in config["checks"]
      assert "firewall-active" in config["checks"]
      assert "uptime" in config["checks"]

    with subtest("sensu client should subscribe as consumer to rabbitmq"):
      machine.wait_until_succeeds("sudo -u rabbitmq rabbitmqctl list_consumers -p /sensu | grep rabbit@machine")

    with subtest("check_ping should be able to ping the VM"):
      machine.succeed("${pkgs.monitoring-plugins}/bin/check_ping localhost -w 200,10% -c 500,30%")
  '';
})
