{ config, pkgs, lib, ... }:
with lib;
let
  markAllowedMetrics = map
    (name: { source_labels = [ "__name__" ];
             regex = "${name}_.*";
             replacement = "yes";
             target_label = "__tmp_globally_allowed"; })
    config.flyingcircus.roles.statshost.globalAllowedMetrics;

  dropUnmarkedMetrics = [
    { source_labels = [ "__tmp_globally_allowed"  ];
      regex = "yes";
      action = "keep"; }
    { regex = "__tmp_globally_allowed";
      action = "labeldrop"; }
  ];

in mkIf config.flyingcircus.roles.statshost.enable
{
  flyingcircus.roles.statshost.prometheusMetricRelabel =
    markAllowedMetrics ++
    dropUnmarkedMetrics ++
    (let
      rename_merge = options: [
        {
          source_labels = [ "__name__" ];
          # Only if there is no command set.
          regex = options.regex;
          replacement = "\${1}";
          target_label = options.target_label;
        }
        {
          source_labels = [ "__name__" ];
          regex = options.regex;
          replacement = options.target_name;
          target_label = "__name__";
        }
      ];
    in
    rename_merge {
      regex = "netstat_tcp_(.*)";
      target_label = "state";
      target_name = "netstat_tcp";
    }
  );
}
