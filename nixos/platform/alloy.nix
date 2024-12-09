{ lib, config, ... }:

let
  enc = config.flyingcircus.enc;
  fclib = config.fclib;

  # XXX support multiple loki servers. unlike with promtail, it may be
  # feasible to send logs to multiple loki instances with a single
  # collector process.
  lokiServer = fclib.findOneService "loki-collector";
in
{
  config = lib.mkIf (!builtins.isNull lokiServer) {
    services.alloy = {
      enable = true;
    };

    # alloy configured though /etc/alloy/config.alloy. see
    # services.alloy documentation for information about
    # reload/restart handling.
    environment.etc."alloy/config.alloy".text = ''
      loki.write "fcio_rg_loki" {
        endpoint {
          url = "http://${lokiServer.address}:3100/loki/api/v1/push"
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
  };
}
