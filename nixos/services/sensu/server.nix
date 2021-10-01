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
      ip46tables -A nixos-fw -i ethsrv -p tcp --dport 5672 -j nixos-fw-accept
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
      partOf = [ "rabbitmq.service" ];
      wantedBy = [ "rabbitmq.service" ];
      after = ["rabbitmq.service" ];
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
        clients = (lib.concatMapStrings (
          client:
            let
              inherit (client) node password;
              name = builtins.head (lib.splitString "." node);
              permissions = [
                "((?!keepalives|results).)*"
                "^(keepalives|results|${name}.*)$"
                "((?!keepalives|results).)*"
              ];
            in ''
              # Configure user and permissions for ${node}:
              rabbitmqctl list_users | grep ^${node} || \
                rabbitmqctl add_user ${node} ${password}

              rabbitmqctl change_password ${client.node} ${password}
              rabbitmqctl set_permissions -p /sensu ${node} ${lib.concatMapStringsSep " " (p: "'${p}'") permissions}
            '')
          sensuClients);
      in
      ''
        # Create user for sensu-server, if it does not exist and make sure that the password is set
        rabbitmqctl list_users | grep sensu-server || \
          rabbitmqctl add_user sensu-server ${serverPassword}

        rabbitmqctl list_vhosts | grep /sensu || \
          rabbitmqctl add_vhost /sensu

        rabbitmqctl set_user_tags sensu-server administrator
        rabbitmqctl change_password sensu-server ${serverPassword}

        rabbitmqctl set_permissions -p /sensu sensu-server ".*" ".*" ".*"

        ${clients}
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
