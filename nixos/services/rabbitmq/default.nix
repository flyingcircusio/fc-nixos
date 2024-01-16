{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.flyingcircus.services.rabbitmq;
  inherit (config) fclib;

  inherit (builtins) concatStringsSep;

  telegrafPassword = fclib.derivePasswordForHost "telegraf";
  sensuPassword = fclib.derivePasswordForHost "sensu";

  config_file_content = lib.generators.toKeyValue {} cfg.configItems;
  config_file = pkgs.writeText "rabbitmq.conf" config_file_content;

  advanced_config_file = pkgs.writeText "advanced.config" cfg.config;

in {
  ###### interface
  options = {
    flyingcircus.services.rabbitmq = {
      enable = mkEnableOption ''
        Whether to enable the RabbitMQ server, an Advanced Message
        Queuing Protocol (AMQP) broker.
      '';

      package = mkOption {
        default = pkgs.rabbitmq-server;
        type = types.package;
        defaultText = "pkgs.rabbitmq-server";
        description = ''
          Which rabbitmq package to use. This service is intended to be used
          with the current stable RabbitMQ version provided by NixOS.
        '';
      };

      listenAddress = mkOption {
        default = "127.0.0.1";
        example = "";
        description = ''
          IP address on which RabbitMQ will listen for AMQP
          connections.  Set to the empty string to listen on all
          interfaces.  Note that RabbitMQ creates a user named
          <literal>guest</literal> with password
          <literal>guest</literal> by default, so you should delete
          this user if you intend to allow external access.

          Together with 'port' setting it's mostly an alias for
          configItems."listeners.tcp.1" and it's left for backwards
          compatibility with previous versions of this module.
        '';
        type = types.str;
      };

      port = mkOption {
        default = 5672;
        description = ''
          Port on which RabbitMQ will listen for AMQP connections.
        '';
        type = types.int;
      };

      dataDir = mkOption {
        type = types.path;
        default = "/var/lib/rabbitmq";
        description = ''
          Data directory for rabbitmq.
        '';
      };

      cookie = mkOption {
        default = "";
        type = types.str;
        description = ''
          Erlang cookie is a string of arbitrary length which must
          be the same for several nodes to be allowed to communicate.
          Leave empty to generate automatically.
        '';
      };

      configItems = mkOption {
        default = {};
        type = types.attrsOf types.str;
        example = ''
          {
            "auth_backends.1.authn" = "rabbit_auth_backend_ldap";
            "auth_backends.1.authz" = "rabbit_auth_backend_internal";
          }
        '';
        description = ''
          Configuration options in RabbitMQ's new config file format,
          which is a simple key-value format that can not express nested
          data structures. This is known as the <literal>rabbitmq.conf</literal> file,
          although outside NixOS that filename may have Erlang syntax, particularly
          prior to RabbitMQ 3.7.0.

          If you do need to express nested data structures, you can use
          <literal>config</literal> option. Configuration from <literal>config</literal>
          will be merged into these options by RabbitMQ at runtime to
          form the final configuration.

          See http://www.rabbitmq.com/configure.html#config-items
          For the distinct formats, see http://www.rabbitmq.com/configure.html#config-file-formats
        '';
      };

      config = mkOption {
        default = "";
        type = types.str;
        description = ''
          Verbatim advanced configuration file contents using the Erlang syntax.
          This is also known as the <literal>advanced.config</literal> file or the old config format.

          <literal>configItems</literal> is preferred whenever possible. However, nested
          data structures can only be expressed properly using the <literal>config</literal> option.

          The contents of this option will be merged into the <literal>configItems</literal>
          by RabbitMQ at runtime to form the final configuration.

          See the second table on http://www.rabbitmq.com/configure.html#config-items
          For the distinct formats, see http://www.rabbitmq.com/configure.html#config-file-formats
        '';
      };

      plugins = mkOption {
        default = [];
        type = types.listOf types.str;
        description = "The names of plugins to enable";
      };

      pluginDirs = mkOption {
        default = [];
        type = types.listOf types.path;
        description = "The list of directories containing external plugins";
      };
    };
  };


  ###### implementation
  config = mkIf cfg.enable {

    # This is needed so we will have 'rabbitmqctl' in our PATH
    environment.systemPackages = [ cfg.package ];
    environment.etc."local/rabbitmq/README.txt".text = ''
      RabbitMQ (${cfg.package.version}) is running on this machine.

      If you need to set non-default configuration options, you can put a
      file called `rabbitmq.config` into this directory. The content of this
      file will be added the configuration of the RabbitMQ service.

      To access rabbitmqctl and other management tools, change into rabbitmq's
      user and run your command(s). Example:

        $ sudo -iu rabbitmq
        % rabbitmqctl status
      '';

    flyingcircus.localConfigDirs.rabbitmq = {
      dir = "/etc/local/rabbitmq";
      user = "rabbitmq";
    };

    services.epmd.enable = true;

    users.users.rabbitmq = {
      description = "RabbitMQ server user";
      home = "${cfg.dataDir}";
      createHome = true;
      group = "rabbitmq";
      uid = config.ids.uids.rabbitmq;
    };

    users.groups.rabbitmq.gid = config.ids.gids.rabbitmq;

    flyingcircus.services.rabbitmq.configItems = {
      "listeners.tcp.1" = mkDefault "${cfg.listenAddress}:${toString cfg.port}";
    };

    flyingcircus.services.rabbitmq = {
      plugins = [ "rabbitmq_management" ];
      # XXX: can we have more than one IP?
      listenAddress = fclib.mkPlatform (head fclib.network.srv.dualstack.addresses);
      config = fclib.configFromFile /etc/local/rabbitmq/rabbitmq.config "";
    };

    systemd.services.rabbitmq = {
      description = "RabbitMQ Server";

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "epmd.socket" ];
      wants = [ "network.target" "epmd.socket" ];

      path = [
        cfg.package
        pkgs.coreutils # mkdir/chown/chmod for preStart
      ];

      environment = {
        RABBITMQ_MNESIA_BASE = "${cfg.dataDir}/mnesia";
        RABBITMQ_LOGS = "-";
        SYS_PREFIX = "";
        RABBITMQ_CONFIG_FILE = config_file;
        RABBITMQ_PLUGINS_DIR = concatStringsSep ":" cfg.pluginDirs;
        RABBITMQ_ENABLED_PLUGINS_FILE = pkgs.writeText "enabled_plugins" ''
          [ ${concatStringsSep "," cfg.plugins} ].
        '';
      } //  optionalAttrs (cfg.config != "") { RABBITMQ_ADVANCED_CONFIG_FILE = advanced_config_file; };

      serviceConfig = {
        ExecStart = "${cfg.package}/sbin/rabbitmq-server";
        ExecStop = "${cfg.package}/sbin/rabbitmqctl shutdown";
        User = "rabbitmq";
        Group = "rabbitmq";
        LogsDirectory = "rabbitmq";
        WorkingDirectory = cfg.dataDir;
        Type = "notify";
        NotifyAccess = "all";
        UMask = "0027";
        LimitNOFILE = "100000";
        Restart = "on-failure";
        RestartSec = "10";
        TimeoutStartSec = "3600";
      };

      preStart = ''
        ${optionalString (cfg.cookie != "") ''
            echo -n ${cfg.cookie} > ${cfg.dataDir}/.erlang.cookie
            chmod 600 ${cfg.dataDir}/.erlang.cookie
        ''}
      '';
    };

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

        for vhost in $(rabbitmqctl list_vhosts -s); do
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
            -u fc-sensu -w ${cfg.listenAddress} -p ${sensuPassword}
        '';
      };

      sensu-client.checks.rabbitmq-node-health = {
        notification = "rabbitmq node healthy";
        command = ''
          ${pkgs.sensu-plugins-rabbitmq}/bin/check-rabbitmq-node-health.rb \
            -u fc-sensu -w ${cfg.listenAddress} -p ${sensuPassword}
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
  };

}
