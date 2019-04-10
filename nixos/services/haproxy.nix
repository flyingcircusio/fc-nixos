{ lib, ... }:
{
  options.flyingcircus.services.haproxy = {
    enable = lib.mkEnableOption "FC-customized HAproxy";
  };
}
