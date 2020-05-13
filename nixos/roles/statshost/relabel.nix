# Relabeling rules that do not fit elsewhere.
# Role-specific rules should be put in the role definitions.

{ config, pkgs, lib, ... }:
with lib;
let
  renameMerge = options: [
    {
      source_labels = [ "__name__" ];
      # Only if there is no command set.
      regex = options.regex;
      replacement = "\${1}";
      target_label = options.targetLabel;
    }
    {
      source_labels = [ "__name__" ];
      regex = options.regex;
      replacement = options.targetName;
      target_label = "__name__";
    }
  ];

  # Drop unwanted labels from InfluxDB metrics.
  influxdbRelabel = let
    removeLabel = label: {
      source_labels = [ "__name__" label ];
      regex = "influxdb_(tsm1|shard)_.*;.+";
      replacement = "";
      target_label = label;
    };
    in map removeLabel [ "path" "walPath" "id" "url" ];

in
{
  flyingcircus.roles.statshost.prometheusMetricRelabel =
    renameMerge {
      regex = "netstat_tcp_(.*)";
      targetLabel = "state";
      targetName = "netstat_tcp";
    } ++
    influxdbRelabel;
}
