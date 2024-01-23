{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;
  mcfg = config.services.mongodb;
  fclib = config.fclib;

  # Fall back to builtins.storePath if `fetchClosure` is not available.
  # Needed when we are upgrading from systems that don't have fetch-closure enabled
  # as experimental feature (or even don't support it at all).
  # Result is the same on a normal system but `fetchClosure` also works in restricted-mode
  # which we use in CI.
  getPkg = path:
    if hasAttr "fetchClosure" builtins then
      fetchClosure {
        fromStore = "https://s3.whq.fcio.net/hydra";
        fromPath = path;
        inputAddressed = true;
      }
    else
      storePath path;

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

  mongodbPkgs = mapAttrs
    (n: v: getPkg v)
    {
      mongodb-3_2 = /nix/store/vjnfmrs99qn0q69d1jlyh1df9jprhsld-mongodb-3.2.22; # 2022_006/19.03
      mongodb-3_4 = /nix/store/shzvfx7bpn804n53igfz053m0y6836ly-mongodb-3.4.24; # 2023_006/21.11
      mongodb-3_6 = /nix/store/wkia38wf48z5x1fy6j06ivldc7qj3h7v-mongodb-3.6.23; # 2024_001/22.11
      mongodb-4_0 = /nix/store/jg8mgbfkyg9vbc68dwizy7vj92gzzsvs-mongodb-4.0.27; # 2024_001/22.11
      mongodb-4_2 = /nix/store/86f2ff9w16whjmq3y0c6aywmxxd27mva-mongodb-4.2.24; # 2024_002/23.05
    };

  mongodbRoles = with config.flyingcircus.roles; {
    "3.2" = mongodb32;
    "3.4" = mongodb34;
    "3.6" = mongodb36;
    "4.0" = mongodb40;
    "4.2" = mongodb42;
  };
  enabledRoles = lib.filterAttrs (n: v: v.enable) mongodbRoles;
  enabledRolesCount = length (lib.attrNames enabledRoles);
  majorVersion = head (lib.attrNames enabledRoles);
  checkPkg =
    if (lib.versionOlder majorVersion "3.6") then
      getPkg /nix/store/c7i75mvqqg1mjk3w6zz1j9cysvch6328-fc-check-mongodb-1.0
    else
      pkgs.fc.check-mongodb;

  checkMongoCmd = "${checkPkg}/bin/check_mongodb";
  extraCheckArgs = head (lib.mapAttrsToList (n: v: v.extraCheckArgs) enabledRoles);

in {
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption "Enable the Flying Circus MongoDB ${v} server role.";
      supportsContainers = fclib.mkEnableContainerSupport;
      extraCheckArgs = with lib; mkOption {
        type = types.str;
        default = if (lib.versionOlder majorVersion "3.6") then "" else "-h localhost -p 27017";
        example = "-h example00.fe.rzob.fcio.net -p 27017 -t -U admin -P /etc/local/mongodb/password.txt";
        description = "Extra arguments to be passed to the check_mongodb script";
      };
    };
  in {
    flyingcircus.roles = {
      mongodb32 = mkRole "3.2";
      mongodb34 = mkRole "3.4";
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
      services.mongodb.package = mongodbPkgs."mongodb-${lib.replaceStrings ["."] ["_"] majorVersion}";

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
              /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb ${extraCheckArgs}
            '';
          };
        } // lib.optionalAttrs (majorVersion != "3.2") {
          # There's no feature compatibility version in 3.2 so we can't check it.
          mongodb_feature_compat_version = {
            notification = "MongoDB is running on an outdated feature compatibility version";
            command = ''
              /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb -A feature_compat_version ${extraCheckArgs}
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

    (lib.mkIf (enabledRolesCount > 0 && lib.versionOlder majorVersion "3.6") {
      # Current telegraf only supports MongoDB 3.6+ so we need to use the package from
      # 22.11 which still supports 3.4 and 3.2.
      services.telegraf.package =
        getPkg /nix/store/bxbhjphivdyp1fdqcz9d3jvnnsrjz8yr-telegraf-1.24.2;
    })
  ];
}
