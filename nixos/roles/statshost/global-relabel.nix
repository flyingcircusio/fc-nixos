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
    dropUnmarkedMetrics;
}
