{ config, lib, pkgs, ... }:

with builtins;
let
  fclib = config.fclib;
in
{
  options =
  let
    mkRole = v: {
      enable = lib.mkEnableOption "Enable the Flying Circus PostgreSQL ${v} server role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };

  in {
    flyingcircus.roles = {
      postgresql96 = mkRole "9.6";
      postgresql10 = mkRole "10";
      postgresql11 = mkRole "11";
      postgresql12 = mkRole "12";
      postgresql13 = mkRole "13";
    };
  };

  config =
  let
    pgroles = with config.flyingcircus.roles; {
      "9.6" = postgresql96.enable;
      "10" = postgresql10.enable;
      "11" = postgresql11.enable;
      "12" = postgresql12.enable;
      "13" = postgresql13.enable;
    };
    enabledRoles = lib.filterAttrs (n: v: v) pgroles;
    enabledRolesCount = length (lib.attrNames enabledRoles);

  in lib.mkMerge [
    (lib.mkIf (enabledRolesCount > 0) {
      assertions =
        [
          {
            assertion = enabledRolesCount == 1;
            message = "PostgreSQL roles are mutually exclusive. Only one may be enabled.";
          }
        ];

      environment.systemPackages = [ config.services.postgresql.package ];
      flyingcircus.services.postgresql.enable = true;
      flyingcircus.services.postgresql.majorVersion =
        head (lib.attrNames enabledRoles);
    })

    {
      flyingcircus.roles.statshost.prometheusMetricRelabel = [
        {
          source_labels = [ "__name__" "datname" ];
          regex = "postgresql_.+;(.+)-[a-f0-9]{12}";
          replacement = "$1";
          target_label = "datname";
        }
        {
          source_labels = [ "__name__" "db" ];
          regex = "postgresql_.+;(.+)-[a-f0-9]{12}";
          replacement = "$1";
          target_label = "db";
        }
      ];
    }
  ];
}
