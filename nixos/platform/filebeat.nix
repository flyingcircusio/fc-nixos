{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.filebeat;

in
{
  config = {
    systemd.services = mapAttrs' (name: value: nameValuePair "filebeat-${name}" (let
      extra = value.extraSettings;
      stateDir = "filebeat/${name}";
      inherit (value) host port;
      config = pkgs.writeText "filebeat-${name}.json"
        (generators.toJSON {} (recursiveUpdate {
          # Logstash output is compatible to Beats input in Graylog.
          output.logstash = {
            hosts = [ "${host}:${toString port}" ];
            ttl = "120s";
            pipelining = 0;
          };
          processors = [];
          # Inputs
          filebeat.inputs = attrValues cfg.inputs;
          # "info" would have some helpful information but also logs every single
          # log shipping (up to once per second) which is too much noise.
          logging.level = "warning";
        } extra));
    in {

      # Only enable the filebeat unit if there are inputs.
      enable = (filterAttrs (name: input: input.enabled) cfg.inputs) != {};

      description = "Ship filebeats to ${host}:${toString port}";
      wantedBy = [ "multi-user.target" ];
      preStart = let
        jq = "${pkgs.jq}/bin/jq";
      in ''
        data_dir=$STATE_DIRECTORY/data
        mkdir -p $data_dir
      '';
      serviceConfig = {
        # Workaround to stop beats from spamming the log with errors about not
        # being able to open a directory at a path which makes no sense.
        # Looks like the metrics code in beats is confused by the file permissions
        # of /sys/fs/cgroup/system.slice/filebeat-journal-*.service/memory.pressure
        # set by systemd 254 when MemoryPressureWatch is enabled. "skip" restores the
        # old behaviour.
        MemoryPressureWatch = "skip";
        StateDirectory = stateDir;
        # DynamicUser = true;
        ExecStart = ''
          ${cfg.package}/bin/filebeat \
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
    })) (cfg.logTargets);
  };

  options = {
    flyingcircus.filebeat = {
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
          Where filebeat should send logs from various files,
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

      inputs = mkOption {
        type = with types; attrsOf anything;
        default = {};
        description = ''
          Inputs for filebeat
        '';
      };

    };
  };
}
