{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;

  mkConfig = { host, port, extraSettings, fields, ... }:
    {
      # Logstash output is compatible to Beats input in Graylog.
      output.logstash = {
        hosts = [ "${host}:${toString port}" ];
        ttl = "120s";
        pipelining = 0;
      };
      processors = [];
      # Read the system journal.
      filebeat.inputs = extraSettings.inputs;
      # "info" would have some helpful information but also logs every single
      # log shipping (up to once per second) which is too much noise.
      logging.level = "warning";

      inherit fields;
    };

  mkService = { name, host, port, extraSettings, fields, package, config }:
  let
    stateDir = "filebeat/${name}";

  in {
    # if more than zero inputs have .enabled set to true
    enable = (filterAttrs (x: x ? enabled && x.enabled) flyingcircus.filebeat.inputs) != {};

    description = "Ship filebeats to ${host}:${toString port}";
    wantedBy = [ "multi-user.target" ];
    preStart = let
      jq = "${pkgs.jq}/bin/jq";
    in ''
      data_dir=$STATE_DIRECTORY/data
      mkdir -p $data_dir
    '';
    serviceConfig = {
      StateDirectory = stateDir;
      # DynamicUser = true;
      ExecStart = ''
        ${package}/bin/filebeat \
          -e \
          -c ${config} \
          -path.data ''${STATE_DIRECTORY}/data
      '';
      Restart = "always";

      # ReadWritePaths = "/var/lib/auditbeat";

      /* ReadWritePaths = map (value: value.paths)
      attrValues (filterAttrs (key: value: value.type == "log") extraSettings.inputs); */

      # Security hardening
      /* CapabilityBoundingSet = "";
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
      ]; */
    };
  };

in
{
  imports = [
    (import ./mkbeat.nix {
      beatName = "filebeat";
      beatData = "logs from various files";
      inherit mkConfig mkService;
      extraSettings = {
        inputs = attrValues config.flyingcircus.filebeat.inputs;
      };
    })
    ({
      options.flyingcircus.filebeat.inputs = mkOption {
        type = with types; attrsOf anything;
        description = ''
          Inputs for filebeat
        '';
      };
    })
  ];
}
