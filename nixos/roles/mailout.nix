# XXX deprecated - migrate to mailstub
{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;

in {
  options = {
    flyingcircus.roles.mailout = {
      enable = lib.mkEnableOption "Deprecated: use mailstub instead";
    };
  };

  config = lib.mkIf config.flyingcircus.roles.mailout.enable {
    flyingcircus.roles.mailstub.enable = !(
      lib.assertMsg false "mailout is deprecated; use mailstub instead");
  };
}
