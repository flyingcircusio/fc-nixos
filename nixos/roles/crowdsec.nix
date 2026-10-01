{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.flyingcircus.roles.crowdsec;
in
{
  options = {
    flyingcircus.roles.crowdsec = {
      enable = lib.mkEnableOption "CrowdSec support";
      enrollKeyFile = lib.mkOption {
        type = lib.types.externalPath;
        description = ''
          The Console Token file to use. The file should just contain the token in the first line of the file like this:

          ```
          hiIamAToken
          ```

          Normally you would do `cscli enroll <token>`,
          but you can put the token in a file instead and pass the path of that file to this option.

          The token is available by clicking the "Enroll command" button at <https://app.crowdsec.net/security-engines?distribution=linux>
        '';
      };

      waf = {
        enable = lib.mkEnableOption "CrowdSec WAF using NGINX";
        appSecPort = lib.mkOption {
          type = lib.types.port;
          default = 7422;
          description = ''
            Port where the AppSec component of CrowdSec listens on.
          '';
        };
      };

      nginxLogAnalysisVirtualHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          NGINX virutal hosts to include in log analysis of crowdstrike.
          The values of this option need to be identical to the attrset key in
          services.nginx.virtualHosts.

          This implies that the full IPs of visitors get stored for 2 days.
        '';
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
        ]
        ++ lib.optionals (cfg.waf.enable) [
          {
            appsec_configs = [ "crowdsecurity/appsec-default" ];
            labels = {
              "type" = "appsec";
            };
            listen_addr = "127.0.0.1:${toString cfg.waf.appSecPort}";
            source = "appsec";
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
        ]
        ++ lib.optionals (cfg.waf.enable) [
          "crowdsecurity/appsec-virtual-patching"
          "crowdsecurity/appsec-generic-rules"
        ];
      };
    };
    services.crowdsec-firewall-bouncer.enable = true;
    flyingcircus.services.sensu-client.checks = {
      crowdsec_lapi_status = {
        notification = "CrowdSec does not listen on";
        command = "/run/wrappers/bin/sudo -u crowdsec ${lib.getExe' config.services.crowdsec.package "cscli"} lapi status";
        interval = 60;
      };
      crowdsec_capi_status = {
        notification = "CrowdSec is not connected to central API";
        command = "/run/wrappers/bin/sudo -u crowdsec ${lib.getExe' config.services.crowdsec.package "cscli"} capi status";
        interval = 600;
      };
    }
    // (lib.optionalAttrs (cfg.waf.enable) {
      crowdsec_appsec_status = {
        notification = "CrowdSec AppSec API is not available";
        command = ''
          ${pkgs.monitoring-plugins}/bin/check_http \
            -H 127.0.0.1 -p 7422 -e 401 -c 5 -w 2
        '';
        interval = 60;
      };
    });
    flyingcircus.passwordlessSudoPackages = [
      {
        commands = [
          "bin/cscli"
        ];
        package = config.services.crowdsec.package;
        groups = [
          "sensuclient"
          "service"
          "sudo-srv"
        ];
        runAs = "crowdsec";
      }
    ];

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

    services.nginx.virtualHosts = lib.genAttrs cfg.nginxLogAnalysisVirtualHosts (vHostName: {
      extraConfig = ''
        access_log /var/log/nginx/crowdsec.log nonanonymized;
      '';
    });
    services.crowdsec-nginx-bouncer = {
      enable = cfg.waf.enable;
      settings = {
        APPSEC_URL = "http://127.0.0.1:${toString cfg.waf.appSecPort}";
      };
    };
  };
}
