{ config, pkgs, lib, ... }:

with builtins;

let

  cfg = config.flyingcircus.services.sensu-server;
  fclib = config.fclib;
  sensuClients = fclib.findServiceClients "sensuserver-server";

  serverPassword = (lib.findSingle
    (x: x.node == "${config.networking.hostName}.gocept.net")
    { password = cfg.serverPassword; } { password = cfg.serverPassword; } sensuClients).password;

  directoryHandler = "${pkgs.fc.agent}/bin/fc-monitor --enc ${config.flyingcircus.encPath} handle-result";

  listenAddress = head fclib.network.srv.dualstack.addresses;

  sensuServerConfigFile =  if (cfg.configFile != null) then cfg.configFile else
    pkgs.writeText "sensu-server.json" ''
      {
        "rabbitmq": {
          "host": "${listenAddress}",
          "user": "sensu-server",
          "password": "${serverPassword}",
          "vhost": "/sensu"
        },
        "handlers": {
          "directory": {
            "type": "pipe",
            "command": "/run/wrappers/bin/sudo ${directoryHandler}"
          },
          "default": {
            "handlers": [],
            "type": "set"
          }
        }
      }
    '';

in {

  options = with lib; {

    flyingcircus.services.sensu-server = {

      enable = mkEnableOption ''
        Enable the Sensu monitoring server daemon.
      '';

      serverPassword = mkOption {
        type = types.str;
        default = "";
      };

      configFile = mkOption {
        type = with types; nullOr path;
        default = null;
        description = "Path to config file. Overrides generated config!";
      };

      extraOpts = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          Extra options used when launching sensu.
        '';
      };

    };
  };

  config = lib.mkIf cfg.enable {

    ##############
    # Sensu Server

    environment.systemPackages = [
      (pkgs.writeScriptBin
        "sensu-server-show-config"
        "cat ${sensuServerConfigFile}")
    ];

    networking.firewall.extraCommands = ''
      ip46tables -A nixos-fw -i ${fclib.network.srv.interface} -p tcp --dport 5672 -j nixos-fw-accept
    '';

    users.extraGroups.sensuserver.gid = config.ids.gids.sensuserver;

    users.users.sensuserver = {
      description = "sensu server daemon user";
      isSystemUser = true;
      uid = config.ids.uids.sensuserver;
      group = "sensuserver";
    };

    security.sudo.extraConfig = ''
      Cmnd_Alias  SENSU_DIRECTORY_HANDLER = ${directoryHandler}
      sensuserver ALL=(root) SENSU_DIRECTORY_HANDLER
    '';

    systemd.services.prepare-rabbitmq-for-sensu = {
      description = "Prepare rabbitmq for sensu-server.";
      wantedBy = [ "multi-user.target" ];
      requires = ["rabbitmq.service" ];
      after = [ "rabbitmq.service" "fc-rabbitmq-settings.service"];
      path = [ config.services.rabbitmq.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "true";
        Restart = "on-failure";
        User = "rabbitmq";
        Group = "rabbitmq";
      };
      script = let
        # Permission settings required for sensu
        # see https://docs.sensu.io/sensu-core/1.7/guides/securing-rabbitmq
        clients = (lib.concatMapStrings
          (client: "${builtins.head (lib.splitString "." client.node)}:${client.node}:${client.password}\n")
          sensuClients);
      in
      ''
        known_users=$(mktemp)
        trap 'rm -f "$known_users"; exit' ERR EXIT  # HUP INT TERM
        rabbitmqctl list_users > $known_users

        echo "Preparing rabbitmq for Sensu ..."

        # Create user for sensu-server, if it does not exist and make sure that the password is set
        grep sensu-server $known_users > /dev/null || \
          rabbitmqctl add_user sensu-server ${serverPassword}

        rabbitmqctl list_vhosts | grep /sensu > /dev/null || \
          rabbitmqctl add_vhost /sensu

        rabbitmqctl set_user_tags sensu-server administrator
        rabbitmqctl change_password sensu-server ${serverPassword}

        rabbitmqctl set_permissions -p /sensu sensu-server ".*" ".*" ".*"

        echo "Ensuring client users ..."
        touch /var/lib/rabbitmq/sensu-clients
        chmod o-r /var/lib/rabbitmq/sensu-clients
        cat > /var/lib/rabbitmq/sensu-clients <<__EOF__
        ${clients}
        __EOF__

        ${pkgs.python38Full}/bin/python -u ${./configure-sensu-clients.py} $known_users
        echo "All done"
      '';
    };

    systemd.services.sensu-server = rec {
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.sensu pkgs.openssl pkgs.bash pkgs.mailutils ];
      requires = [
        "rabbitmq.service"
        "redis.service" ];
      after = requires;
      serviceConfig = {
        User = "sensuserver";
        ExecStart = "${pkgs.sensu}/bin/sensu-server -c ${sensuServerConfigFile} " +
          "--log_level warn";
        Restart = "always";
        RestartSec = "5s";
      };
      environment = {
        EMBEDDED_RUBY = "false";
        # Hide annoying warnings, old Sensu is not developed anymore.
        RUBYOPT="-W0";
      };

      # rabbitmq needs some time to start up. The wait for pid
      # in the default service config doesn't really seem to help :(
      preStart = ''
          sleep 5
      '';
    };

  };

}
