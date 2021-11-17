# XXX deprecated - migrate to mailstub
{ config, lib, pkgs, ... }:

with builtins;

let
  roles = config.flyingcircus.roles;
  fclib = config.fclib;
in {
  options = {
    flyingcircus.roles.mailout = {
      enable = lib.mkEnableOption "Deprecated: use mailstub instead";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = lib.mkIf config.flyingcircus.roles.mailout.enable {
    flyingcircus.roles.mailstub.enable = !(
      lib.assertMsg false "mailout is deprecated; use mailstub instead");
  };
}
