{ lib, config, ... }:

let
  enc = config.flyingcircus.enc;
  fclib = config.fclib;

  # XXX support multiple loki servers. the upstream docs note: "It is
  # generally recommended to run multiple Promtail clients in parallel
  # if you want to send to multiple remote Loki instances."
  lokiServer = fclib.findOneService "loki-collector";
in
{
  config = lib.mkIf (!builtins.isNull lokiServer) {
    services.promtail = {
      enable = true;
      configuration = {
        # don't expose the http and grpc api
        server.disable = true;

        clients = [{
          url = "http://${lokiServer.address}:3100/loki/api/v1/push";
        }];

        scrape_configs = [{
          job_name = "systemd-journal";
          journal = {
            json = true;
            # there are server side limits to how many labels loki
            # will accept on log lines. consider them a scarce
            # resource and use them sparingly.
            labels = {
              resource_group = enc.parameters.resource_group;
              location = enc.parameters.location;
              hostname = config.networking.hostName;
            };
          };
          relabel_configs = [
            {
              source_labels = [ "__journal__systemd_unit" ];
              target_label = "systemd_unit";
            }
            {
              source_labels = [ "__journal_syslog_identifier" ];
              target_label = "syslog_identifier";
            }
          ];
        }];
      };
    };
  };
}
