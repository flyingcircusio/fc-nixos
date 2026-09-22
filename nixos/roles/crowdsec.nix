{ config, lib, ... }:
let
  cfg = config.flyingcircus.roles.crowdsec;
in
{
  options = {
    flyingcircus.roles.crowdsec = {
      enable = lib.mkEnableOption "CrowdSec support";
      enrollKeyFile = lib.mkOption {
        type = lib.types.externalPath;
      };

      nginx = {
        enabledVirtualHosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            NGINX virutal hosts to include in log analysis of crowdstrike.
            The values of this option need to be identical to the attrset key in
            services.nginx.virtualHosts.

            This implies that the full IPs of visitors get stored for 2 days.
          '';
        };
      };

      remediations = {
        ipRemediationDuration = lib.mkOption {
          type = lib.types.str;
          default = "4h";
        };
        rangeRemediationDuration = lib.mkOption {
          type = lib.types.str;
          default = "4h";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.crowdsec = {
      enable = true;
      readOnlyPaths = [
        "/var/log/nginx"
      ];
      autoUpdateService = true;
      settings = {
        config.api.server.online_client.credentials_path =
          "${config.services.crowdsec.settings.config.config_paths.data_dir}/online_api_credentials.yaml";
        console.enrollKeyFile = cfg.enrollKeyFile;
        acquisitions = [
          {
            source = "file";
            filenames = [
              "/var/log/nginx/crowdsec.log"
            ];
            labels = {
              type = "nginx";
            };
          }
        ];
        profiles = [
          {
            name = "default_ip_remediation";
            filters = [ "Alert.Remediation == true && Alert.GetScope() == 'Ip'" ];
            decisions = [
              {
                type = "ban";
                duration = cfg.remediations.ipRemediationDuration;
              }
            ];
            on_success = "break";
          }
          {
            name = "default_range_remediation";
            filters = [ "Alert.Remediation == true && Alert.GetScope() == 'Range'" ];
            decisions = [
              {
                type = "ban";
                duration = cfg.remediations.rangeRemediationDuration;
              }
            ];
            on_success = "break";
          }
        ];
      };
      hub = {
        collections = [
          "crowdsecurity/linux"
          "crowdsecurity/nginx"
          "crowdsecurity/base-http-scenarios"
        ];
      };
    };
    services.crowdsec-firewall-bouncer.enable = true;

    # NGINX
    services.logrotate.settings."nginx-crowdsec" = {
      # higher than PL default 900
      ignoreduplicates = true;
      priority = 901;
      files = [ "/var/log/nginx/crowdsec.log" ];
      rotate = 1;
      create = "0644 nginx nginx";
      su = "nginx nginx";
      frequency = "daily";
      postrotate = "[ ! -f /var/run/nginx/nginx.pid ] || kill -USR1 `cat /var/run/nginx/nginx.pid`";
    };

    services.nginx.virtualHosts = lib.genAttrs cfg.nginx.enabledVirtualHosts (vHostName: {
      extraConfig = ''
        access_log /var/log/nginx/crowdsec.log nonanonymized;
      '';
    });
  };
}
