{ config, lib, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.webgateway;
  kubernetesServer = fclib.findOneService "k3s-server-server";
  fclib = config.fclib;
in
{
  options = {

    flyingcircus.roles.webgateway = with lib; {
      enable = mkEnableOption "FC web gateway role (nginx/haproxy)";
      supportsContainers = fclib.mkEnableContainerSupport;
    };
  };

  config = lib.mkMerge [

  (lib.mkIf cfg.enable {
    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.haproxy.enable = true;
  })

  (lib.mkIf (cfg.enable && kubernetesServer != null) {
    flyingcircus.services.k3s-frontend.enable = true;
  })
  ];
}
