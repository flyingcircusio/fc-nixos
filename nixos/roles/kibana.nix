{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.kibana;
  fclib = config.fclib;
  esUrlFile = "/etc/local/kibana/elasticSearchUrl";
  esCfg = config.services.elasticsearch;

  # Determine the Elasticsearch URL, in order:
  # 1. elasticSearchUrl option
  # 2. URL from local config
  # 3. Local Elasticsearch service
  # 4. no URL, don't activate Kibana
  elasticSearchUrl =
    if cfg.elasticSearchUrl == null
    then
      if pathExists esUrlFile
      then
        (lib.removeSuffix "\n" (readFile esUrlFile))
      else
        if esCfg.enable
        then "http://${esCfg.listenAddress}:${toString esCfg.port}"
        else null
    else cfg.elasticSearchUrl;

  kibanaShowConfig = pkgs.writeScriptBin "kibana-show-config" ''
    cat $(systemctl cat kibana | grep "ExecStart" | cut -d" " -f3)
  '';

  kibanaVersion =
    if config.flyingcircus.roles.kibana6.enable
    then "6"
    else if config.flyingcircus.roles.kibana7.enable
    then "7"
    else null;

  enabled = kibanaVersion != null;
in
{
  options = with lib; {

    flyingcircus.roles.kibana = {

      # Just a virtual role, needs version selection.
      supportsContainers = fclib.mkDisableContainerSupport;

      elasticSearchUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://elasticsearchhost:9200";
      };

    };

    flyingcircus.roles.kibana6 = {
      enable = mkEnableOption "Enable the Flying Circus Kibana 6 role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };

    flyingcircus.roles.kibana7 = {
      enable = mkEnableOption "Enable the Flying Circus Kibana 7 role.";
      supportsContainers = fclib.mkEnableContainerSupport;
    };

  };

  config = lib.mkMerge [
    (lib.mkIf (enabled && elasticSearchUrl != null) {

      environment.systemPackages = [
        kibanaShowConfig
      ];

      services.kibana = {
        enable = true;
        extraConf = lib.optionalAttrs (kibanaVersion == "7") {
          xpack.reporting.enabled = false;
        };

        # Unlike elasticsearch, kibana cannot listen to both IPv4 and IPv6.
        # We choose to use IPv4 here.
        listenAddress = head fclib.network.srv.v4.addresses;
        package = pkgs."kibana${kibanaVersion}";
      } // lib.optionalAttrs (kibanaVersion == "6") {
          elasticsearch.url = elasticSearchUrl;
      } // lib.optionalAttrs (kibanaVersion == "7") {
          elasticsearch.hosts = [ elasticSearchUrl ];
      };

      systemd.services.kibana.serviceConfig = {
        Restart = "always";
      };
    })

    (lib.mkIf enabled {
      environment.etc."local/kibana/README.txt".text = ''
        Kibana local configuration

        To configure the ElasticSearch Kibana connects to, add a file `elasticSearchUrl`
        here, and put the URL in.

        If no URL has been set and ElasticSearch is running on this machine the local
        ElasticSearch is used automatically.

        Run `sudo fc-manage --build` to activate the configuration.
      '';

      flyingcircus.localConfigDirs.kibana = {
        dir = "/etc/local/kibana";
      };
    })

  ];
}
