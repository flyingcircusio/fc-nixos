{ config, pkgs, lib, ... }:
with lib;
let
  # Add metric prefixes here that should be accepted by the central statshost.
  # Replaces flyingcircus.statshost.globalAllowedMetrics in role code.
  globalAllowedMetrics = [
    # We don't have apache on 19.03 but we still have 15.09 VMs using it.
    "apache"
    "elasticsearch"
    "graylog"
    "haproxy"
    "memcached"
    "mongodb"
    "mysql"
    "nginx"
    "postfix"
    "postgresql"
    "rabbitmq"
    "redis"
    "varnish"
  ];

  markAllowedMetrics = map
    (name: { source_labels = [ "__name__" ];
             regex = "${name}_.*";
             replacement = "yes";
             target_label = "__tmp_globally_allowed"; })
    config.flyingcircus.roles.statshost-global.allowedMetricPrefixes;

  dropUnmarkedMetrics = [
    { source_labels = [ "__tmp_globally_allowed" ];
      regex = "yes";
      action = "keep"; }
    { regex = "__tmp_globally_allowed";
      action = "labeldrop"; }
  ];

in mkIf config.flyingcircus.roles.statshost-global.enable
{
  # Telegraf host metrics are added in platform/monitoring.nix.
  flyingcircus.roles.statshost-global.allowedMetricPrefixes =
    [ "influxdb" ] ++ globalAllowedMetrics;

  flyingcircus.roles.statshost.prometheusMetricRelabel =
    lib.mkAfter (markAllowedMetrics ++ dropUnmarkedMetrics);
}
