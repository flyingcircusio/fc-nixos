{ config, lib, pkgs, ... }:

with builtins;
{
  options = 
  let
    mkRole = v: lib.mkEnableOption
      "Enable the Flying Circus PostgreSQL ${v} server role.";
  in {
    flyingcircus.roles = {
      postgresql95.enable = mkRole "9.5";
      postgresql96.enable = mkRole "9.6";
      postgresql10.enable = mkRole "10";
      postgresql11.enable = mkRole "11";
    };
  };

  config = 
  let
    pgroles = with config.flyingcircus.roles; {
      "9.5" = postgresql95.enable;
      "9.6" = postgresql96.enable;
      "10" = postgresql10.enable;
      "11" = postgresql11.enable;
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

      flyingcircus.services.postgresql.enable = true;
      flyingcircus.services.postgresql.majorVersion = 
        head (lib.attrNames enabledRoles);
    })

    {
      flyingcircus.roles.statshost.globalAllowedMetrics = [ "postgresql" ];
    }
  ];
}
