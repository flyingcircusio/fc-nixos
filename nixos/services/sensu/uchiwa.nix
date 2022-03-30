{ config, lib, pkgs, ... }:

with builtins;

let

  uchiwa = pkgs.uchiwa;

  cfg = config.flyingcircus.services.uchiwa;

  apiServers = filter
    (x: x.service == "sensuserver-api")
    config.flyingcircus.encServices;

  uchiwaConfigFile = let
    apiServersConfig = (lib.concatMapStringsSep ",\n" (
      apiServer:
        ''
          {
            "name": "${apiServer.location}",
            "host": "sensu.${apiServer.location}.gocept.net",
            "port": 443,
            "ssl": true,
            "insecure": true,
            "path": "/api",
            "timeout": 30,
            "user": "sensuserver-api"  ,
            "pass": "${apiServer.password}"
           }'')
      apiServers);
    in pkgs.writeText "uchiwa.json" ''
    {
      "sensu": ${if (cfg.serverConfig != null) then (toJSON cfg.serverConfig) else "[${apiServersConfig}]"},
      "uchiwa": {
        "host": "0.0.0.0",
        "port": 3000,
        "refresh": 30,
        "loglevel": "warn",
        "users": ${config.flyingcircus.services.uchiwa.users}
      }
    }
  '';

in {

  options = with lib; {

    flyingcircus.services.uchiwa = {

      enable = mkEnableOption "Enable the Uchiwa sensu dashboard daemon.";

      users = mkOption {
        type = types.lines;
        default = ''
        []
        '';
        description = ''
          User configuration to insert into the configuration file.
        '';
      };

      extraOpts = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          Extra options used when launching uchiwa.
        '';
      };

      serverConfig = mkOption {
        default = null;
      };

    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      (pkgs.writeScriptBin
        "uchiwa-show-config"
        "cat ${uchiwaConfigFile}")
    ];

    flyingcircus.services.uchiwa.users =
      toJSON (
        map (user: { username = user; password = "{crypt}${config.users.users."${user}".hashedPassword}"; })
        config.users.groups.login.members);

    users.extraGroups.uchiwa.gid = config.ids.gids.uchiwa;

    users.users.uchiwa = {
      description = "uchiwa daemon user";
      isSystemUser = true;
      uid = config.ids.uids.uchiwa;
      group = "uchiwa";
    };

    systemd.services.uchiwa = {
      wantedBy = [ "multi-user.target" ];
      path = [ uchiwa ];
      serviceConfig = {
        User = "uchiwa";
        ExecStart = "${uchiwa}/bin/uchiwa -c ${uchiwaConfigFile} -p ${uchiwa}/public";
        Restart = "always";
      };
    };

  };

}
