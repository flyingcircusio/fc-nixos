{ lib, pkgs, ... }:
{
  imports = with lib; [
    # old -> new
    # redis and redis4 roles do the same
    (mkRenamedOptionModule [ "flyingcircus" "roles" "redis4" ] [ "flyingcircus" "roles" "redis" ])
    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
    (mkRemovedOptionModule [ "flyingcircus" "roles" "mysql" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
