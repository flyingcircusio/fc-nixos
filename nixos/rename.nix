{ lib, pkgs, ... }:
{
  imports = with lib; [
    # old -> new
    # redis and redis4 roles do the same
    (mkRenamedOptionModule [ "flyingcircus" "roles" "redis4" ] [ "flyingcircus" "roles" "redis" ])
  ];
}
