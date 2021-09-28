{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.journalbeat;

in
  {
    config = {
      systemd.services = mapAttrs' (name: value: nameValuePair "journalbeat-${name}" (let
        extra = value.extraSettings;
        stateDir = "journalbeat/${name}";
        inherit (value) host port;
        config = pkgs.writeText "journalbeat-${name}.json"
          (generators.toJSON {} (recursiveUpdate {
            # Logstash output is compatible to Beats input in Graylog.
            output.logstash = {
              hosts = [ "${host}:${toString port}" ];
              ttl = "120s";
              pipelining = 0;
            };
            # Read the system journal.
            journalbeat.inputs  = [ { paths = []; } ];
            # "info" would have some helpful information but also logs every single
            # log shipping (up to once per second) which is too much noise.
            logging.level = "warning";
          } extra));
      in {
        description = "Ship system journal to ${host}:${toString port}";
        wantedBy = [ "multi-user.target" ];
        preStart = let
          jq = "${pkgs.jq}/bin/jq";
        in ''
          data_dir=$STATE_DIRECTORY/data
          mkdir -p $data_dir
          if ! grep -sq cursor $data_dir/registry; then
            echo "Journal cursor not present, initalizing it to the end of the journal."
            cursor=$(journalctl --output-fields=_ -o json -n1 | ${jq} -r '.__CURSOR')
            echo "Reading starts at: $cursor"
            ${jq} -n --arg cursor $cursor \
              '{journal_entries: [{path: "LOCAL_SYSTEM_JOURNAL", cursor: $cursor}]}' \
              > $data_dir/registry
          fi

        '';
        serviceConfig = {
          StateDirectory = stateDir;
          SupplementaryGroups = [ "systemd-journal" ];
          DynamicUser = true;
          ExecStart = ''
            ${cfg.package}/bin/journalbeat \
              -e \
              -c ${config} \
              -path.data ''${STATE_DIRECTORY}/data
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
            Where journalbeat should send logs from the journal,
            using the logstash output.
            This can be Graylog instances with Beats input, for example.
            By default, send logs to a resource group loghost if present
            and a central one.
          '';
        };

        package = mkOption {
          type = types.package;
          default = pkgs."journalbeat7";
          defaultText = "pkgs.journalbeat7";
          example = literalExample "pkgs.journalbeat7";
          description = ''
            The journalbeat package to use.
          '';
        };

      };
    };
  }
