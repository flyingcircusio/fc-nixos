{
  config,
  lib,
  pkgs,
  ...
}:

with builtins;
let
  fclib = config.fclib;
in
{
  options =
    let
      mkRole = v: {
        enable = lib.mkEnableOption "Enable the Flying Circus PostgreSQL ${v} server role.";
        supportsContainers = fclib.mkEnableDevhostSupport;
      };

    in
    {
      flyingcircus.roles = {
        postgresql14 = mkRole "14";
        postgresql15 = mkRole "15";
        postgresql16 = mkRole "16";
        postgresql17 = mkRole "17";
        postgresql18 = mkRole "18";
      };
    };

  config =
    let
      pgroles = with config.flyingcircus.roles; {
        "14" = postgresql14.enable;
        "15" = postgresql15.enable;
        "16" = postgresql16.enable;
        "17" = postgresql17.enable;
        "18" = postgresql18.enable;
      };
      enabledRoles = lib.filterAttrs (n: v: v) pgroles;
      enabledRolesCount = length (lib.attrNames enabledRoles);

    in
    lib.mkMerge [
      (lib.mkIf (enabledRolesCount > 0) {
        assertions = [
          {
            assertion = enabledRolesCount == 1;
            message = "PostgreSQL roles are mutually exclusive. Only one may be enabled.";
          }
        ];

        environment.systemPackages = [ config.services.postgresql.package ];
        flyingcircus.services.postgresql.enable = true;
        flyingcircus.services.postgresql.majorVersion = head (lib.attrNames enabledRoles);
      })

      {
        flyingcircus.roles.statshost.prometheusMetricRelabel = [
          {
            source_labels = [
              "__name__"
              "datname"
            ];
            regex = "postgresql_.+;(.+)-[a-f0-9]{12}";
            replacement = "$1";
            target_label = "datname";
          }
          {
            source_labels = [
              "__name__"
              "db"
            ];
            regex = "postgresql_.+;(.+)-[a-f0-9]{12}";
            replacement = "$1";
            target_label = "db";
          }
        ];
      }
    ];
}
