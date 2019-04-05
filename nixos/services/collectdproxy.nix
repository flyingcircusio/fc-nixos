# Collectdproxy relays metrics from Gentoo hosts to the infrastructure-central
# statshost. We need a collectdproxy for each location.
# Data flow:
# collectd (Gentoo) ->
# collectdproxy.location (per-location collector) ->
# collectdproxy.statshost (central statshost) ->
# influx (central statshost)
{ config, lib, pkgs, ... }:

with lib;

let
  cfg_loc = config.flyingcircus.services.collectdproxy.location;
  cfg_stats = config.flyingcircus.services.collectdproxy.statshost;

in {
  options.flyingcircus.services.collectdproxy = {

    location = {
      enable = mkEnableOption "outgoing proxy in for a location";

      statshost = mkOption {
        type = types.str;
        description = "FQDN of the central statshost";
        example = "stats.example.com";
      };

      listenAddr = mkOption {
        type = types.str;
        description = "Bind to host/IP address";
        default = "localhost";
      };
    };

    statshost = {
      enable = mkEnableOption "incoming proxy on the central statshost";

      sendTo = mkOption {
        type = types.str;
        description = "Where to send the uncompressed data to (host:port)";
        default = "localhost:2003";
      };
    };

  };

  config = mkMerge [

    (mkIf cfg_loc.enable  {
      systemd.services.collectdproxy-location = rec {
        description = "collectd Location proxy";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network.target" ];
        after = wants;
        serviceConfig = {
          ExecStart = ''
            ${pkgs.fc.collectdproxy}/bin/location-proxy \
              -s ${cfg_loc.statshost} \
              -l ${cfg_loc.listenAddr}
          '';
          Restart = "always";
          RestartSec = "60s";
          User = "nobody";
          Type = "simple";
        };
      };
    })

   (mkIf cfg_stats.enable {
      systemd.services.collectdproxy-statshost = rec {
        description = "collectd Statshost proxy";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network.target" ];
        after = wants;
        serviceConfig = {
          ExecStart = ''
            ${pkgs.fc.collectdproxy}/bin/statshost-proxy -s ${cfg_stats.sendTo}
          '';
          Restart = "always";
          RestartSec = "60s";
          User = "nobody";
          Type = "simple";
        };
      };
    })
  ];
}
