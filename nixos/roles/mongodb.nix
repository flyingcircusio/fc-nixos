{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;
  mcfg = config.services.mongodb;
  fclib = config.fclib;

  listenAddresses =
    fclib.network.lo.dualstack.addresses ++
    fclib.network.srv.dualstack.addresses;

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

  checkMongoCmd = "${pkgs.fc.check-mongodb}/bin/check_mongodb";

  mongodbRoles = with config.flyingcircus.roles; {
    "3.6" = mongodb36.enable;
    "4.0" = mongodb40.enable;
    "4.2" = mongodb42.enable;
  };
  enabledRoles = lib.filterAttrs (n: v: v) mongodbRoles;
  enabledRolesCount = length (lib.attrNames enabledRoles);
  majorVersion = head (lib.attrNames enabledRoles);

in {
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption "Enable the Flying Circus MongoDB ${v} server role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  in {
    flyingcircus.roles = {
      mongodb36 = mkRole "3.6";
      mongodb40 = mkRole "4.0";
      mongodb42 = mkRole "4.2";
    };
  };

  config = lib.mkMerge [

    (lib.mkIf (enabledRolesCount > 0) {
      assertions =
        [
          {
            assertion = enabledRolesCount == 1;
            message = "MongoDB roles are mutually exclusive. Only one may be enabled.";
          }
        ];

      environment.systemPackages = [
        pkgs.mongodb-tools
      ];

      services.mongodb.enable = true;
      services.mongodb.dbpath = "/srv/mongodb";
      services.mongodb.bind_ip = fclib.mkPlatform (lib.concatStringsSep "," listenAddresses);
      services.mongodb.pidFile = "/run/mongodb.pid";
      services.mongodb.package = pkgs."mongodb-${lib.replaceStrings ["."] ["_"] majorVersion}";

      systemd.services.mongodb = {
        preStart = "echo never > /sys/kernel/mm/transparent_hugepage/defrag";
        postStop = "echo always > /sys/kernel/mm/transparent_hugepage/defrag";
        # intial creating of journal takes ages
        serviceConfig.TimeoutStartSec = fclib.mkPlatform 1200;
        serviceConfig.LimitNOFILE = 64000;
        serviceConfig.LimitNPROC = 32000;
        serviceConfig.Restart = "always";
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

      flyingcircus.infrastructure.preferNoneSchedulerOnSsd = true;

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

      services.logrotate.settings = {
        "/var/log/mongodb/*.log" = {
          nocreate = true;
          postrotate = "systemctl reload mongodb";
        };
      };

      flyingcircus.services = {

        sensu-client.checks = {
          mongodb = {
            notification = "MongoDB alive";
            command = ''
              /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb
            '';
          };

          mongodb_feature_compat_version = {
            notification = "MongoDB is running on an outdated feature compatibility version";
            command = ''
              /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb -A feature_compat_version
            '';
            interval = 600;
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
