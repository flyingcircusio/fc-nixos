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

in
{
  options = {

    flyingcircus.roles.kibana = with lib; {
      enable = mkEnableOption "Enable the Flying Circus Kibana server role.";

      elasticSearchUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://elasticsearchhost:9200";
      };

    };

  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && elasticSearchUrl != null) {

      environment.systemPackages = [
        kibanaShowConfig
      ];

      services.kibana = {
        enable = true;
        # Unlike elasticsearch, kibana cannot listen to both IPv4 and IPv6.
        # We choose to use IPv4 here.
        listenAddress = head (fclib.listenAddresses "ethsrv");
        elasticsearch.url = elasticSearchUrl;
      };

      systemd.services.kibana.serviceConfig = {
        Restart = "always";
      };
    })

    (lib.mkIf cfg.enable {
      environment.etc."local/kibana/README.txt".text = ''
        Kibana local configuration

        To configure the ElasticSearch Kibana connects to, add a file `elasticSearchUrl`
        here, and put the URL in.

        If no URL has been set and ElasticSearch is running on this machine the local
        ElasticSearch is used automatically.

        Run `sudo fc-manage --build` to activate the configuration.
      '';

      flyingcircus.localConfigDirs.systemd = {
        dir = "/etc/local/kibana";
      };
    })

  ];
}
