{ lib, config, ... }:

let
  enc = config.flyingcircus.enc;
  fclib = config.fclib;

  # XXX support multiple loki servers. unlike with promtail, it may be
  # feasible to send logs to multiple loki instances with a single
  # collector process.

  prometheusServer = fclib.findOneService "statshost-master-collector";
  prometheusHost = lib.replaceStrings [ "gocept.net" ] [ "fcio.net" ] prometheusServer.address;
  prometheusPort = 9090;

  lokiServer = fclib.findOneService "loki-collector";
  tempoServer = fclib.findOneService "tempo-collector";
  lokiPort = 3100;

  tempoHost = lib.replaceStrings [ "gocept.net" ] [ "fcio.net" ] tempoServer.address;
  tempoPort = 4317;
in
{
  config = lib.mkMerge [
    (lib.mkIf (!isNull prometheusServer) {
      environment.etc."alloy/prometheus.alloy".text = ''
        prometheus.remote_write "fcio_rg_prometheus" {
          endpoint {
            url = "http://${prometheusHost}:${toString prometheusPort}"
          }
        }
      '';
    })

    (lib.mkIf (!isNull lokiServer) {
      services.alloy = {
        enable = true;
      };

      # alloy configured though /etc/alloy/config.alloy. see
      # services.alloy documentation for information about
      # reload/restart handling.
      environment.etc."alloy/loki.alloy".text = ''
        loki.write "fcio_rg_loki" {
          endpoint {
            url = "http://${lokiServer.address}:${toString lokiPort}/loki/api/v1/push"
          }

          // there are server side limits to how many labels loki
          // will accept on log lines. consider them a scarce
          // resource and use them sparingly.
          external_labels = {
            resource_group = "${enc.parameters.resource_group}",
            location = "${enc.parameters.location}",
            hostname = "${config.networking.hostName}",
          }
        }

        loki.relabel "fcio_journal" {
          forward_to = []
          rule {
            source_labels = ["__journal__systemd_unit"]
            target_label = "systemd_unit"
          }
          rule {
            source_labels = ["__journal_syslog_identifier"]
            target_label = "syslog_identifier"
          }
        }

        loki.source.journal "fcio_journal" {
          forward_to = [loki.write.fcio_rg_loki.receiver]
          relabel_rules = loki.relabel.fcio_journal.rules
          format_as_json = true  // match promtail config
        }
      '';
    })

    (lib.mkIf (!isNull tempoServer) {
      services.alloy = {
        enable = true;
      };

      # alloy configured though /etc/alloy/config.alloy. see
      # services.alloy documentation for information about
      # reload/restart handling.
      environment.etc."alloy/tempo.alloy".text = ''
        otelcol.exporter.otlp "fcio_rg_tempo" {
            retry_on_failure {
                max_elapsed_time = "1m0s"
            }

            client {
                endpoint = "${tempoHost}:${toString tempoPort}"
            }
        }

      '';
    })

    (lib.mkIf ((!isNull lokiServer) && (!isNull tempoServer)) {
      environment.etc."alloy/otelcol.alloy".text =
        let
          v4 = builtins.head config.fclib.network.srv.v4.addresses;
        in
        ''
          otelcol.exporter.loki "fcio_rg_otlp_loki" {
            forward_to = [loki.write.fcio_rg_loki.receiver]
          }
          otelcol.exporter.prometheus "fcio_rg_otlp_prometheus" {
            forward_to =  [prometheus.remote_write.fcio_rg_prometheus.receiver]
          }

          otelcol.receiver.otlp "fcio_rg_otlp" {
            grpc {
              endpoint = "${v4}:4319"
            }
            http {
              endpoint = "${v4}:4320"
            }

            output {
              metrics = [otelcol.exporter.prometheus.fcio_rg_otlp_prometheus.input]
              logs   = [otelcol.exporter.loki.fcio_rg_otlp_loki.input]
              traces = [otelcol.exporter.otlp.fcio_rg_tempo.input]
            }
          }
        '';
    })
  ];
}
