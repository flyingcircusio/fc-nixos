{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.services.rabbitmq365Frozen;
  inherit (config) fclib;
  listenAddress = head (fclib.network.srv.v4.addresses);
  telegrafPassword = fclib.derivePasswordForHost "telegraf";
  sensuPassword = fclib.derivePasswordForHost "sensu";
in
{
  options = with lib; {
    flyingcircus.services.rabbitmq365Frozen = {
      enable = mkEnableOption "RabbitMQ server, an Advanced Message Queuing Protocol (AMQP) broker (3.6.x series)";

      package = mkOption {
        type = types.package;
        default = storePath /nix/store/sqap94f4a0z8pxdal5wfgsm83ncwwbbd-rabbitmq-server-3.6.5;
        description = ''
          Which rabbitmq package to use. Should be the same as used in `service`.
        '';
      };

      service = mkOption {
        type = types.package;
        example =
          literalExpression
            "builtins.storePath /nix/store/4vn6482k7vhafyqdq1lvw9yyb37agv8z-unit-rabbitmq.service;";
        description = ''
          Which rabbitmq service package to use. The package is expected to
          contain a `rabbitmq.service` unit file. This is usually generated
          from running config on NixOS 20.09 using the "freeze" script from
          the role documentation.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [ cfg.package ];

    flyingcircus.localConfigDirs.rabbitmq = {
      dir = "/etc/local/rabbitmq";
      user = "rabbitmq";
    };

    environment.etc."local/rabbitmq/README.txt".text = ''
      This machine runs RabbitMQ 3.6.5 with "frozen" config.
      The configuration of RabbitMQ cannot be changed via this directory or NixOS options anymore.
    '';

    flyingcircus.services = {

      sensu-client.checks.rabbitmq-alive = {
        notification = "rabbitmq amqp alive";
        command = ''
          ${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-amqp-alive.rb \
            -u fc-sensu -w ${listenAddress} -p ${sensuPassword}
        '';
      };

      sensu-client.checks.rabbitmq-node-health = {
        notification = "rabbitmq node healthy";
        command = ''
          ${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb \
            -u fc-sensu -w ${listenAddress} -p ${sensuPassword}
        '';
      };

      telegraf.inputs.rabbitmq = [
        {
          client_timeout = "10s";
          header_timeout = "10s";
          url = "http://${config.networking.hostName}:15672";
          username = "fc-telegraf";
          password = telegrafPassword;
          nodes = [ "rabbit@${config.networking.hostName}" ];
          # Drop string fields. They are converted to labels in Prometheus
          # which blows up the number of metrics.
          fielddrop = [ "idle_since" ];
        }
      ];
    };

    systemd.packages = [
      (pkgs.runCommand "rabbitmq-3.6.5-service" {} ''
        service_dir=$out/lib/systemd/system
        mkdir -p $service_dir
        cp ${cfg.service}/rabbitmq.service $service_dir
      '')
      ];

    systemd.services.fc-rabbitmq-settings = {
      description = "Check/update FCIO rabbitmq settings (for monitoring)";
      requires = [ "rabbitmq.service" ];
      after = [ "rabbitmq.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ cfg.package ];
      serviceConfig = {
        Type = "oneshot";
        User = "rabbitmq";
        Group = "rabbitmq";
      };

      script = ''
        # Delete user guest, if it's there with default password, and
        # administrator privileges.
        rabbitmqctl list_users | grep guest && \
          rabbitmqctl delete_user guest

        # Create user for telegraf, if it does not exist and make sure that the password is set
        rabbitmqctl list_users | grep fc-telegraf || \
          rabbitmqctl add_user fc-telegraf ${telegrafPassword}

        rabbitmqctl change_password fc-telegraf ${telegrafPassword}

        # Create user for sensu, if it does not exist and make sure that the password is set
        rabbitmqctl list_users | grep fc-sensu || \
          rabbitmqctl add_user fc-sensu ${sensuPassword}

        rabbitmqctl change_password fc-sensu ${sensuPassword}

        rabbitmqctl set_user_tags fc-telegraf monitoring || true
        rabbitmqctl set_user_tags fc-sensu monitoring || true

        for vhost in $(rabbitmqctl list_vhosts -q); do
          rabbitmqctl set_permissions fc-telegraf -p "$vhost" "" "" ".*"
        done

        rabbitmqctl set_permissions fc-sensu "^aliveness-test$" "^amq\.default$" "^(amq\.default|aliveness-test)$"
      '';
    };

    systemd.timers.fc-rabbitmq-settings = {
      description = "Runs the FC RabbitMQ preparation script regularly.";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitActiveSec = "1h";
        AccuracySec = "10m";
      };
    };

    users.users.rabbitmq = {
      description = "RabbitMQ server user";
      home = "/var/lib/rabbitmq";
      shell = "/run/current-system/sw/bin/bash";
      createHome = true;
      group = "rabbitmq";
      uid = config.ids.uids.rabbitmq;
    };

    users.groups.rabbitmq.gid = config.ids.gids.rabbitmq;

  };

}
