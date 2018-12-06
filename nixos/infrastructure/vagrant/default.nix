{ config, lib, ... }:

{
  config = lib.mkIf (config.flyingcircus.infrastructureModule == "vagrant") {
  };
}
