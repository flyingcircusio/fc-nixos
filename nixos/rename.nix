{ lib, pkgs, ... }:
{
  imports = with lib; [
    # old -> new
    # redis and redis4 roles do the same
    (mkRenamedOptionModule [ "flyingcircus" "roles" "redis4" ] [ "flyingcircus" "roles" "redis" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshostproxy" ] [ "flyingcircus" "roles" "statshost-location-proxy" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "enable" ] [ "flyingcircus" "roles" "statshost-global" "enable" ])
    (mkRenamedOptionModule [ "flyingcircus" "roles" "statshost" "globalAllowedMetrics" ] [ "flyingcircus" "roles" "statshost-global" "allowedMetricPrefixes" ])
    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
    (mkRemovedOptionModule [ "flyingcircus" "roles" "mysql" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
