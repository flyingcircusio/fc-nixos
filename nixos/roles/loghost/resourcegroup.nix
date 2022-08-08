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

    flyingcircus.roles.loghost = {
      enable = lib.mkEnableOption ''
        Flying Circus Loghost role.
        This role enables the full graylog stack at once (GL, ES, Mongo).
      '';
      supportsContainers = fclib.mkDisableContainerSupport;
    };
  };

  config = lib.mkIf (cfg.enable) {

    flyingcircus.roles.graylog = {
      enable = true;
      cluster = false;
      serviceTypes = [ "loghost-server" ];
    };

    flyingcircus.services.graylog = {
      heapPercentage = fclib.mkPlatform (15 * heapCorrection / 100);
      elasticsearchHosts = [
        "http://${config.networking.hostName}:9200"
      ];
    };

    # Graylog 3.x wants Elasticsearch 6, ES7 does not work (yet).
    flyingcircus.roles.elasticsearch6.enable = true;
    flyingcircus.roles.elasticsearch = {
      clusterName = "graylog";
      esNodes = [ config.networking.hostName ];
      heapPercentage = fclib.mkPlatform (35 * heapCorrection / 100);
      # Disable automatic index creation which can mess up the
      # index structure expected by Graylog and prevent index rotation.
      # Graylog writes data to an alias called graylog_deflector which has
      # to be created before writing to it. We didn't have this setting in the
      # past and saw that graylog_deflector was sometimes
      # automatically created as an index by ES.
      # Recommended by Graylog docs (https://archivedocs.graylog.org/en/3.3/pages/installation/os/centos.html).
      extraConfig = ''
        action.auto_create_index: false
      '';
    };

  };

}
