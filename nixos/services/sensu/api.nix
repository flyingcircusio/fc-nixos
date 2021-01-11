{ config, pkgs, lib, ... }:

with builtins;

let

  sensu = pkgs.sensu;

  cfg = config.flyingcircus.services.sensu-api;
  serverCfg = config.flyingcircus.services.sensu-server;

  # Duplicated from server.nix.
  fclib = config.fclib;
  sensuClients = fclib.findServiceClients "sensuserver-server";

  serverPassword = (lib.findSingle
    (x: x.node == "${config.networking.hostName}.gocept.net")
    { password = ""; } { password = ""; } sensuClients).password;

  apiPassword = (lib.findSingle
    (x: x.address == "${config.networking.hostName}.gocept.net")
    { password = ""; } { password = ""; } (fclib.findServices "sensuserver-api")).password;

  listenAddress = head (fclib.listenAddresses "ethsrv");

  sensuApiConfigFile = if (cfg.configFile != null) then cfg.configFile else
    pkgs.writeText "sensu-api.json" ''
      {
        "rabbitmq": {
          "host": "${listenAddress}",
          "user": "sensu-server",
          "password": "${serverPassword}",
          "vhost": "/sensu"
        },
        "api": {
          "user": "sensuserver-api",
          "password": "${apiPassword}"
        }
      }
    '';

in  {

  options = with lib; {
    flyingcircus.services.sensu-api = {

      enable = lib.mkEnableOption ''
          Enable the Sensu monitoring API daemon.
        '';

      configFile = mkOption {
        type = with types; nullOr path;
        default = null;
        description = "Path to config file. Overrides generated config!";
      };

    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      (pkgs.writeScriptBin
        "sensu-api-show-config"
        "cat ${sensuApiConfigFile}")
    ];

    users.extraGroups.sensuapi.gid = config.ids.gids.sensuapi;

    users.extraUsers.sensuapi = {
      description = "sensu api daemon user";
      uid = config.ids.uids.sensuapi;
      group = "sensuapi";
    };

    systemd.services.sensu-api = rec {
      wantedBy = [ "multi-user.target" ];
      requires = [
        "rabbitmq.service"
        "redis.service"
      ];
      after = requires;
      path = [ sensu ];
      serviceConfig = {
        User = "sensuapi";
        ExecStart = "${sensu}/bin/sensu-api -L warn -c ${sensuApiConfigFile}";
        Restart = "always";
        RestartSec = "5s";
      };
    };

  };

}
