{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;

  mkConfig = { host, port, extra, ... }:
    {
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
    } // extra;

  mkService = { name, host, port, extra, package, config, ... }:
  let
    stateDir = "journalbeat/${name}";

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
        ${package}/bin/journalbeat \
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
  };

in
  {
    imports = [
      (import ./mkbeat.nix {
        beatName = "journalbeat";
        beatData = "logs from the journal";
        inherit mkConfig mkService;
      })
    ];
  }
