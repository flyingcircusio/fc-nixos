{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.loghost;
  fclib = config.fclib;

  # It's common to have stathost and loghost on the same node. Each should
  # use half of the memory then. A general approach for this kind of
  # multi-service would be nice.
  heapCorrection =
    if config.flyingcircus.roles.statshost-master.enable
    then 50
    else 100;

in
{

  options = {

    flyingcircus.roles.loghost.enable = lib.mkEnableOption ''
      Flying Circus Loghost role.
      This role enables the full graylog stack at once (GL, ES, Mongo).
    '';

  };

  config = lib.mkIf (cfg.enable) {

    flyingcircus.roles.graylog = fclib.mkPlatform {
      enable = true;
      cluster = false;
      serviceTypes = [ "loghost-server" ];
    };

    flyingcircus.services.graylog = fclib.mkPlatform {
      heapPercentage = 15 * heapCorrection / 100;
      elasticsearchHosts = [
        "http://${config.networking.hostName}.${config.networking.domain}:9200"
      ];
    };

    # Graylog 3.x wants Elasticsearch 6, ES7 does not work (yet).
    flyingcircus.roles.elasticsearch6.enable = true;
    flyingcircus.roles.elasticsearch = fclib.mkPlatform {
      dataDir = "/var/lib/elasticsearch";
      clusterName = "graylog";
      heapPercentage = 35 * heapCorrection / 100;
    };

  };

}
