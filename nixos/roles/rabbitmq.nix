{ config, lib, pkgs, ... }:

with builtins;

{
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption
        "Enable the Flying Circus RabbitMQ ${v} server role.";
    };
  in {
    flyingcircus.roles = {
      rabbitmq36_5 = mkRole "3.6.5";
      rabbitmq36_15 = mkRole "3.6.15";
      rabbitmq38 = mkRole "3.8";
    };
  };

  config =
  let
    # XXX: We choose the first IP of ethsrv here, as the 3.6 service is not capable
    # of handling more than one IP.
    listenAddress = head (fclib.listenAddresses "ethsrv");

    roles = config.flyingcircus.roles;
    fclib = config.fclib;

    telegrafPassword = fclib.derivePasswordForHost "telegraf";
    sensuPassword = fclib.derivePasswordForHost "sensu";

    rabbitRoles = with config.flyingcircus.roles; {
      "3.6.5" = rabbitmq36_5.enable;
      "3.6.15" = rabbitmq36_15.enable;
      "3.8" = rabbitmq38.enable;
    };
    enabledRoles = lib.filterAttrs (n: v: v) rabbitRoles;
    enabledRolesCount = length (lib.attrNames enabledRoles);
    enabled = enabledRolesCount > 0;
    roleVersion = head (lib.attrNames enabledRoles);
    majorMinorVersion = lib.concatStringsSep "." (lib.take 2 (splitVersion roleVersion));
    package = pkgs."rabbitmq-server_${replaceStrings ["."] ["_"] roleVersion}";

    extraConfig = fclib.configFromFile /etc/local/rabbitmq/rabbitmq.config "";

    serviceConfig = {
      inherit listenAddress package;
      enable = true;
      plugins = [ "rabbitmq_management" ];
      config = extraConfig;
    };

  in lib.mkMerge [
    (lib.mkIf (enabled && majorMinorVersion == "3.6") {
      flyingcircus.services.rabbitmq36 = serviceConfig;
    })

    (lib.mkIf (enabled && majorMinorVersion != "3.6") {
      flyingcircus.services.rabbitmq = serviceConfig;
    })

    (lib.mkIf enabled {
      assertions =
        [
          {
            assertion = enabledRolesCount == 1;
            message = "RabbitMQ roles are mutually exclusive. Only one may be enabled.";
          }
        ];

      users.extraUsers.rabbitmq = {
        shell = "/run/current-system/sw/bin/bash";
      };

      flyingcircus.passwordlessSudoRules = [
        # Service users may switch to the rabbitmq system user
        {
          commands = [ "ALL" ];
          groups = [ "sudo-srv" "service" ];
          runAs = "rabbitmq";
        }
      ];

      flyingcircus.localConfigDirs.rabbitmq = {
        dir = "/etc/local/rabbitmq";
        user = "rabbitmq";
      };

      environment.etc."local/rabbitmq/README.txt".text = ''
        RabbitMQ (${package.version}) is running on this machine.

        If you need to set non-default configuration options, you can put a
        file called `rabbitmq.config` into this directory. The content of this
        file will be added the configuration of the RabbitMQ service.

        To access rabbitmqctl and other management tools, change into rabbitmq's
        user and run your command(s). Example:

          $ sudo -iu rabbitmq
          % rabbitmqctl status
        '';

      systemd.services.fc-rabbitmq-settings = {
        description = "Check/update FCIO rabbitmq settings (for monitoring)";
        requires = [ "rabbitmq.service" ];
        after = [ "rabbitmq.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ package ];
        serviceConfig = {
          Type = "oneshot";
          User = "rabbitmq";
          Group = "rabbitmq";
        };

        script =
        let
          # 3.7 returns table headers in list_* results, we must suppress that with -s
          quietParam = if (lib.versionOlder package.version "3.7") then "-q" else "-s";
        in ''
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

            for vhost in $(rabbitmqctl list_vhosts ${quietParam}); do
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

    })

    {
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        {
          regex = "idle_since";
          action = "labeldrop";
        }
      ];
    }
  ];
}
