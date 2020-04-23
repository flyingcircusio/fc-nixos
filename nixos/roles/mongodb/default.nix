{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;
  mcfg = config.services.mongodb;
  fclib = config.fclib;

  listenAddresses =
    fclib.listenAddresses "lo" ++
    fclib.listenAddresses "ethsrv";

  localConfig = fclib.configFromFile /etc/local/mongodb/mongodb.yaml "";

  # Use a completely own version of mongodb.conf (not resorting to NixOS
  # defaults). The stock version includes a hard-coded "syslog = true"
  # statement.
  mongoCnf = pkgs.writeText "mongodb.yaml" ''
    net.bindIp: "${mcfg.bind_ip}"
    net.ipv6: true

    ${lib.optionalString mcfg.quiet "systemLog.quiet: true"}
    systemLog.path: /var/log/mongodb/mongodb.log
    systemLog.destination: file
    systemLog.logAppend: true
    systemLog.logRotate: reopen

    storage.dbPath: ${mcfg.dbpath}

    processManagement.fork: true
    processManagement.pidFilePath: ${mcfg.pidFile}

    ${lib.optionalString (mcfg.replSetName != "") "replication.replSetName: ${mcfg.replSetName}"}

    ${mcfg.extraConfig}
    ${localConfig}
  '';

  checkMongoCmd = (pkgs.callPackage ./check.nix {}) + /bin/check_mongo;

in {
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption "Enable the Flying Circus MongoDB ${v} server role.";
    };
  in {
    flyingcircus.roles = {
      mongodb32 = mkRole "3.2";
      mongodb34 = mkRole "3.4";
    };
  };

  config =
  let
    package =
      if roles.mongodb32.enable
      then pkgs.mongodb_3_2
      else if roles.mongodb34.enable
      then pkgs.mongodb
      else null;

  in lib.mkMerge [
   (lib.mkIf (package != null) {

      assertions = [
        {
          assertion = roles.mongodb32.enable != roles.mongodb34.enable;
          message = "MongoDB roles are mutually exclusive. Only one may be enabled.";
        }
      ];

      environment.systemPackages = [
        pkgs.mongodb-tools
      ];

      services.mongodb.enable = true;
      services.mongodb.dbpath = "/srv/mongodb";
      services.mongodb.bind_ip = lib.concatStringsSep "," listenAddresses;
      services.mongodb.pidFile = "/run/mongodb.pid";
      services.mongodb.package = package;

      systemd.services.mongodb = {
        preStart = "echo never > /sys/kernel/mm/transparent_hugepage/defrag";
        postStop = "echo always > /sys/kernel/mm/transparent_hugepage/defrag";
        # intial creating of journal takes ages
        serviceConfig.TimeoutStartSec = fclib.mkPlatform 1200;
        serviceConfig.LimitNOFILE = 64000;
        serviceConfig.LimitNPROC = 32000;
        serviceConfig.ExecStart = lib.mkForce ''
          ${mcfg.package}/bin/mongod --config ${mongoCnf}
        '';
        reload = ''
          if [[ -f ${mcfg.pidFile} ]]; then
            kill -USR1 $(< ${mcfg.pidFile} )
          fi
        '';
      };

      users.users.mongodb = {
        shell = "/run/current-system/sw/bin/bash";
        home = "/srv/mongodb";
      };

      flyingcircus.activationScripts = {

        mongodb-dirs = lib.stringAfter [ "users" "groups" ] ''
          install -d -o mongodb /{srv,var/log}/mongodb
        '';

      };

      flyingcircus.localConfigDirs.mongodb = {
        dir = "/etc/local/mongodb";
        user = "mongodb";
      };

      security.sudo.extraRules = [
        # Service users may switch to the mongodb system user
        {
          commands = [ { command = "ALL"; options = [ "NOPASSWD" ]; } ];
          groups = [ "sudo-srv" "service" ];
          runAs = "mongodb";
        }
        {
          commands = [ { command = checkMongoCmd; options = [ "NOPASSWD" ]; } ];
          users = [ "sensuclient" ];
          runAs = "mongodb";
        }
      ];

      environment.etc."local/mongodb/README.txt".text = ''
        Put your local mongodb configuration into `mongodb.yaml` here.
        It will be joined with the basic config.
      '';

      services.logrotate.config = ''
        /var/log/mongodb/*.log {
          nocreate
          postrotate
            systemctl reload mongodb
          endscript
        }
      '';

      flyingcircus.services = {

        sensu-client.checks = {
          mongodb = {
            notification = "MongoDB alive";
            command = ''
              /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb
            '';
          };
        };

        sensu-client.expectedConnections = {
          warning = 60000;
          critical = 63000;
        };

        telegraf.inputs = {
          mongodb = [
            {
              servers = ["mongodb://127.0.0.1:27017"];
              gather_perdb_stats = true;
            }
          ];
        };

      };
    })
  ];
}
