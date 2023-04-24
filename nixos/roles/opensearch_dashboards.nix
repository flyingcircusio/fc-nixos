{ config, lib, pkgs, ... }:

with builtins;

let
  cfg = config.flyingcircus.roles.opensearch_dashboards;
  fclib = config.fclib;
  opensearchCfg = config.services.opensearch;

  # Determine the opensearch URL, in order:
  # 1. opensearchUrl option
  # 2. Local opensearch service
  # 3. no URL, don't activate opensearchDashboards
  opensearchUrl =
    if cfg.opensearchUrl != null
    then cfg.opensearchUrl
    else
      if opensearchCfg.enable
      then "http://${opensearchCfg.settings."network.host"}:${toString opensearchCfg.settings."http.port"}"
      else null;

  opensearchDashboardsShowConfig = pkgs.writeScriptBin "opensearch-dashboards-show-config" ''
    cat $(systemctl cat opensearch-dashboards | grep "ExecStart" | cut -d" " -f3)
  '';

in
{
  options = with lib; {

    flyingcircus.roles.opensearch_dashboards = {

      enable = mkEnableOption "Enable the Flying Circus opensearch dashboards role.";
      supportsContainers = fclib.mkEnableContainerSupport;

      opensearchUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://opensearchhost:9200";
      };

    };

  };

  config = (lib.mkIf (cfg.enable && opensearchUrl != null) {
    environment.systemPackages = [
      opensearchDashboardsShowConfig
    ];

    flyingcircus.services.opensearch-dashboards = {
      enable = true;
      # Unlike opensearch, opensearch-dashboards cannot listen to both IPv4 and IPv6.
      # We choose to use IPv4 here.
      listenAddress = head fclib.network.srv.v4.addresses;
      opensearch.hosts = [ opensearchUrl ];
    };

    systemd.services.opensearch-dashboards.serviceConfig = {
      Restart = "always";
    };
  });

}
