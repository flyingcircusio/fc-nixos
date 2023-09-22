{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.journalbeat;
  journalSetCursor = fclib.python3BinFromFile ./filebeat-journal-set-cursor.py;

in
  {
    config = {
      systemd.services = mapAttrs' (name: value: nameValuePair "filebeat-journal-${name}" (let
        inherit (value) host port;
        extra = value.extraSettings;
        stateDir = "filebeat-journal/${name}";
        statePath = "/var/lib/" + stateDir;
        oldStateDir = "journalbeat/${name}";
        oldStatePath = "/var/lib/" + oldStateDir;
        config = pkgs.writeText "filebeat-journal-${name}.json"
          (generators.toJSON {} (recursiveUpdate {
            # Logstash output is compatible to Beats input in Graylog.
            output.logstash = {
              hosts = [ "${host}:${toString port}" ];
              ttl = "120s";
              pipelining = 0;
            };
            # Read the system journal.
            filebeat.inputs = [{
              type = "journald";
              id = "everything";
              paths = [];
              seek = "cursor";
            }];

            # "info" would have some helpful information but also logs every single
            # log shipping (up to once per second) which is too much noise.
            # "warning" is still annoying because of the error:
            # "route ip+net: netlinkrib: address family not supported by protocol"
            logging.level = "error";
          } extra));
      in {
        description = "Ship system journal to ${host}:${toString port}";
        wantedBy = [ "multi-user.target" ];
          preStart = ''
            set -e
            ${journalSetCursor}/bin/filebeat-journal-set-cursor \
              ${statePath}/data/registry/filebeat \
              ${oldStatePath}/data/registry
            rm -rf ${oldStatePath}/data || true
          '';
        serviceConfig = {
          StateDirectory = [
            oldStateDir
            stateDir
          ];
          SupplementaryGroups = [ "systemd-journal" ];
          DynamicUser = true;
          ExecStart = ''
            ${cfg.package}/bin/filebeat \
              -e \
              -c ${config} \
              -path.data ${statePath}/data
          '';
          Restart = "always";

          # Security hardening
          CapabilityBoundingSet = "";
          DevicePolicy = "closed";
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          PrivateDevices = true;
          PrivateUsers = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "seccomp"
          ];
        };
      })) (cfg.logTargets);
    };

    options = {
      flyingcircus.journalbeat = {
        fields = mkOption {
          type = types.attrs;
          default = {};
          description = ''
            Additional fields that are added to each log message.
            They appear as field_<name> in the log message.
          '';
         };

        logTargets = mkOption {
          type = with types; attrsOf (submodule {
            options = {
              host = mkOption { type = str; };
              port = mkOption { type = int; };
              extraSettings = mkOption { type = attrs; default = {}; };
            };
          });
          default = config.flyingcircus.beats.logTargets;
          description = ''
            Where filebeat should send logs from the journal,
            using the logstash output.
            This can be Graylog instances with Beats input, for example.
            By default, send logs to a resource group loghost if present
            and a central one.
          '';
        };

        package = mkOption {
          type = types.package;
          default = pkgs.filebeat7-oss;
          defaultText = "pkgs.filebeat7-oss";
          example = literalExample "pkgs.filebeat7";
          description = ''
            The filebeat package to use.
          '';
        };

      };
    };
  }
