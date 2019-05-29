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
      rabbitmq37 = mkRole "3.7";
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
      "3.7" = rabbitmq37.enable;
    };
    enabledRoles = lib.filterAttrs (n: v: v) rabbitRoles;
    enabledRolesCount = length (lib.attrNames enabledRoles);
    enabled = enabledRolesCount > 0;
    roleVersion = head (lib.attrNames enabledRoles);
    majorMinorVersion = lib.concatStringsSep "." (lib.take 2 (splitVersion roleVersion));
    package = pkgs."rabbitmq_server_${replaceStrings ["."] ["_"] roleVersion}";
  
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

    (lib.mkIf (enabled && majorMinorVersion == "3.7") {
      flyingcircus.services.rabbitmq37 = serviceConfig;
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

      security.sudo.extraConfig = ''
        # Service users may switch to the rabbitmq system user
        %sudo-srv ALL=(rabbitmq) ALL
        %service ALL=(rabbitmq) ALL
      '';

      # We use this in this way in favor of setting PermissionsStartOnly to
      # true as other script expect running as rabbitmq user
      system.activationScripts.fcio-rabbitmq = ''
        install -d -o ${toString config.ids.uids.rabbitmq} -g service -m 02775 \
          /etc/local/rabbitmq/
      '';

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
        description = "Prepare rabbitmq for operation in FC.";
        requires = [ "rabbitmq.service" ];
        after = [ "rabbitmq.service" ];
        wantedBy = [ "multi-user.target" ];
        path = [ package ];
        serviceConfig = {
          Type = "oneshot";
          User = "rabbitmq";
          Group = "rabbitmq";
          RemainAfterExit = true;
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
          Unit = "fc-rabbitmq-settings";
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
            url = "http://${config.networking.hostName}:15672";
            username = "fc-telegraf";
            password = telegrafPassword;
            nodes = [ "rabbit@${config.networking.hostName}" ];
          }
        ];

      };

    })

    {
      flyingcircus.roles.statshost.globalAllowedMetrics = [ "rabbitmq" ];
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        { regex = "idle_since";
          action = "labeldrop"; }
      ];
    }
  ];
}
