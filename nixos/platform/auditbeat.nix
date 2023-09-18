{ pkgs, lib, config, ... }:

with lib;

let
  fclib = config.fclib;
  cfg = config.flyingcircus.auditbeat;

in
{
  options.flyingcircus.auditbeat = with lib; {
    package = mkOption {
      type = types.package;
      default = pkgs.auditbeat7-oss;
      defaultText = "pkgs.auditbeat7-oss";
      example = literalExpression "pkgs.auditbeat7";
      description = ''
        The auditbeat package to use.
      '';
    };
  };

  # TODO: remove mkIf after beta
  config = mkIf (config.flyingcircus.audit.enable) {
    flyingcircus.filebeat.inputs.auditbeat = {
      type = "log";
      enabled = true;
      paths = [
        "/var/lib/auditbeat/auditbeat"
      ];
      json = {
        keys_under_root = true;
        overwrite_keys = true;
      };
    };

    systemd.services.auditbeat = let
      # ref https://github.com/elastic/beats/blob/master/auditbeat/auditbeat.reference.yml
      auditbeatCfgFile = pkgs.writeText "auditbeat.json"
        (generators.toJSON {} (
          {
            # Output to filebeat
            output.file = {
              enabled = true;
              path = "/var/lib/auditbeat";
              filename = "auditbeat";
            };
            # Read from auditd
            auditbeat.modules = [
              {
                module = "auditd";
                audit_rules = concatStringsSep "\n" config.security.audit.rules;
              }
            ];

            /* processors = [
              { add_host_metadata = "~"; }
              { add_cloud_metadata = "~"; }
              { add_docker_metadata = "~"; }
            ]; */
            # "info" would have some helpful information but also logs every single
            # log shipping (up to once per second) which is too much noise.
            logging.level = "warning";
          }
        ));

    in {
      description = "Ship audit data to filebeat";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        StateDirectory = "auditbeat";
        SupplementaryGroups = [ "systemd-journal" ];
        # DynamicUser = true;
        ExecStart = ''
          ${cfg.package}/bin/auditbeat \
            -e \
            -c ${auditbeatCfgFile} \
            -path.data ''${STATE_DIRECTORY}/data
        '';
        Restart = "always";

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
        ProtectSystem = "strict"; */
        # TODO: allow audit addresses
        # RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        /* RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "seccomp"
        ]; */
      };
    };
  };
}
