{ config, lib, pkgs, ... }:

with builtins;

let
  inherit (config) fclib;
  cfg = config.flyingcircus.services.ferretdb;
  checkMongoCmd = "${pkgs.fc.check-mongodb}/bin/check_mongodb";
in
{
  options = with lib; {
    flyingcircus.services.ferretdb = {
      enable = mkEnableOption "Enable FerretDB, a (mostly) drop-in replacement for MongoDB";
      supportsContainers = fclib.mkEnableContainerSupport;

      address = mkOption {
        type = types.str;
        default = head fclib.network.srv.v4.addresses;
        defaultText = "First SRV IPv4 address";
        description = "Address to listen to. FerretDB only supports listen on a single address.";
      };

      extraCheckArgs = with lib; mkOption {
        type = types.str;
        default = "-h ${cfg.address} -p ${toString cfg.port}";
        example = "-h example00.fe.rzob.fcio.net -p 27017 -t";
        description = "Extra arguments to be passed to the check_mongodb script";
      };

      port = mkOption {
        type = types.port;
        default = 27017;
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {

      environment.systemPackages = with pkgs; [
        mongodb-tools
        fc.check-mongodb
        mongosh
        ferretdb
      ];

      flyingcircus.services.postgresql.enable = true;
      flyingcircus.services.postgresql.majorVersion = "16";
      flyingcircus.services.postgresql.autoUpgrade = {
        enable = true;
        expectedDatabases = [ "ferretdb" ];
      };

      flyingcircus.services.sensu-client = {
        checks = {
          ferretdb = {
            notification = "FerretDB not functional";
            command = ''
              ${checkMongoCmd} -d ferretdb ${cfg.extraCheckArgs}
            '';
          };
        };

        expectedConnections = {
          warning = 60000;
          critical = 63000;
        };
      };

      services.ferretdb = {
        enable = true;
        settings = {
          FERRETDB_HANDLER = "pg";
          FERRETDB_LISTEN_ADDR = fclib.mkPlatform "${cfg.address}:${toString cfg.port}";
          FERRETDB_POSTGRESQL_URL = fclib.mkPlatform "postgres:///ferretdb?host=/run/postgresql&user=ferretdb";
          FERRETDB_TELEMETRY = "disable";
        };
      };

      services.postgresql.ensureDatabases = [ "ferretdb" ];
      services.postgresql.ensureUsers = [{
        name = "ferretdb";
        ensureDBOwnership = true;
      }];

      systemd.services.ferretdb = {
        serviceConfig = {
          stopIfChanged = false;
        };
      };

    })
  ];
}
