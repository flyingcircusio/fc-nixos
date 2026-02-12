{
  config,
  lib,
  ...
}:
let
  cfg = config.flyingcircus.roles.faro;
  fclib = config.fclib;
in
{
  options = with lib; {
    flyingcircus.roles.faro = {
      enable = mkEnableOption "Flying Circus Grafana Faro Frontend configuration";
      supportsContainers = fclib.mkEnableDevhostSupport;

      host = fclib.mkRoleOption "faro" {
        type = lib.types.str;
        description = "Hostname for the frontend";
        default = c: c.hostname;
      };

      api_key = fclib.mkRoleOption "faro" {
        type = types.str;
        description = "api key to authenticate metrics sent by the frontend";
        default = c: c.api_key;
      };

      allowed_origins = fclib.mkRoleOption "faro" {
        type = types.listOf types.str;
        description = "allowed origins for CORS";
        # NOTE this needs to be passed as a list in the role_configuration json
        default = c: c.allowed_origins;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # See https://github.com/grafana/faro-web-sdk/blob/main/docs/sources/tutorials/quick-start-browser.md
    environment.etc."alloy/faro-integration.alloy".text = ''
      loki.process "logs_process_client" {
          forward_to = [loki.write.fcio_rg_loki.receiver]

          // TODO consider making this processing stage configurable? otherwise scrap it and route output from faro.receiver to loki directly
          stage.logfmt {
              mapping = { "kind" = "", "service_name" = "", "app" = "" }
          }

          stage.labels {
              values = { "kind" = "kind", "service_name" = "service_name", "app" = "app" }
          }
      }


      faro.receiver "integrations_app_agent_receiver" {
          server {
              listen_address           = "127.0.0.1"
              listen_port              = 8060
              cors_allowed_origins     = ${builtins.toJSON cfg.allowed_origins}
              api_key                  = "${cfg.api_key}"
              max_allowed_payload_size = "10MiB"

              rate_limiting {
                  rate = 100
              }
          }

          sourcemaps { }

          output {
              logs   = [loki.process.logs_process_client.receiver]
              traces = [otelcol.exporter.otlp.fcio_rg_tempo.input]
          }
      }

    '';

    services.nginx.virtualHosts.${cfg.vhost} = {
      http2 = true;
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:8060";
    };
  };
}
