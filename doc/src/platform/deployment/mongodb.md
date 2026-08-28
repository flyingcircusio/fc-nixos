---
global_sync_id: "v1"
---

# How to deploy a MongoDB

By default, it's recommended to use the MongoDB packages provided by upstream NixOS.
All provided packages can be found in [our package search](https://search.flyingcircus.io/search/packages?q=mongodb&channel=fc-23.11-production).

Please keep in mind that NixOS doesn't provide binaries for MongoDB due to
the license not being OSI-approved.

The following versions of MongoDB are regularly built by Hydra for platform
releases:

| Version | Attribute | min. platform release |
| --- | --- | --- |
| 6.0.x | `pkgs.mongodb-6_0` | for 23.11: 2024_019, part of 24.05 or newer |

For legacy setups, the following store-paths are available in our binary cache
and can be used to run old versions of MongoDB:

| Version | Store Path | Platform release |
| --- | --- | --- |
| 4.0.27 | `/nix/store/jg8mgbfkyg9vbc68dwizy7vj92gzzsvs-mongodb-4.0.27` | 2024_001/22.11 |
| 4.2.24 | `/nix/store/86f2ff9w16whjmq3y0c6aywmxxd27mva-mongodb-4.2.24` | 2024_002/23.05 |

NixOS has support for providing a MongoDB systemd service.
It can be configured as follows in `/etc/local/nixos/mongodb.nix`:

```nix
{ config, lib, pkgs, ... }:
let
  inherit (config) fclib;

  mcfg = config.services.mongodb;

  listenAddresses =
    fclib.network.lo.dualstack.addresses ++
    fclib.network.srv.dualstack.addresses;

  checkPkg = pkgs.fc.check-mongodb;
  checkMongoCmd = "${checkPkg}/bin/check_mongodb";
  extraCheckArgs = "-h localhost -p 27017";

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
  '';
in {
  environment.systemPackages = [
    pkgs.mongodb-tools
  ];

  services.mongodb = {
    enable = true;
    dbpath = "/srv/mongodb";
    bind_ip = lib.concatStringsSep "," listenAddresses;
    pidFile = "/run/mongodb.pid";
    package = throw "Please replace this `throw ...` expression with 'builtins.storePath /nix/store/…'";
    enableAuth = true;

    # WARNING: this will only work on the very first install.
    # You need to change MongoDB's root password manually later on.
    initialRootPassword = throw "Please replace this `throw ...` expression with the initial root password of the mongodb root account";

    # WARNING: don't set this on the initial install of MongoDB!
    # Otherwise the initialRootPassword won't be set.
    #replSetName = "replica";
  };

  systemd.services.mongodb = {
    preStart = "echo never > /sys/kernel/mm/transparent_hugepage/defrag";
    postStop = "echo always > /sys/kernel/mm/transparent_hugepage/defrag";
    # intial creating of journal takes ages
    serviceConfig.TimeoutStartSec = lib.mkForce 1200;
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

  # Only needed when using `pkgs.mongodb-X_Y`
  flyingcircus.allowedUnfreePackageNames = [ "mongodb" ];

  flyingcircus.infrastructure.preferNoneSchedulerOnSsd = true;

  flyingcircus.activationScripts = {
    mongodb-dirs = lib.stringAfter [ "users" "groups" ] ''
      install -d -o mongodb /{srv,var/log}/mongodb
    '';
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

  /*
    Logrotation for logfiles created by mongodb.

    If nothing else was configured, logfiles will be removed after
    14 days.

    Rotations happen daily.
   */
  services.logrotate.settings = {
    "/var/log/mongodb/*.log" = {
      nocreate = true;
      postrotate = "systemctl reload mongodb";
    };
  };

  flyingcircus.services = {
    /*
      Adds custom sensu checks for mongodb implemented by our platform.

      This checks whether it can connect to MongoDB and whether the
      feature compatibility version matches the running version.
     */
    sensu-client.checks = {
      mongodb = {
        notification = "MongoDB alive";
        command = ''
          /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb ${extraCheckArgs}
        '';
      };
      mongodb_feature_compat_version = {
        notification = "MongoDB is running on an outdated feature compatibility version";
        command = ''
          /run/wrappers/bin/sudo -u mongodb -- ${checkMongoCmd} -d mongodb -A feature_compat_version ${extraCheckArgs}
        '';
        interval = 600;
      };
    };

    /*
      Increases the max. allowed network connections to this VM
      before the sensu alert gets red.
     */
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
}
```

Additional configuration for MongoDB can be appended into the contents of `mongoCnf`.
