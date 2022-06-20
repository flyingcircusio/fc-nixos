{ config, pkgs, lib, ... }:
with lib;
let
  # Add metric prefixes here that should be accepted by the central statshost.
  # Replaces flyingcircus.statshost.globalAllowedMetrics in role code.
  # This also includes the host metrics from telegraf defined in platform/monitoring.nix.
  globalAllowedMetrics = [
    # We don't have apache on 19.03 but we still have 15.09 VMs using it.
    "apache"
    "ceph"
    "cpu"
    "disk"
    "diskio"
    "elasticsearch"
    "graylog"
    "haproxy"
    "kernel"
    "mem"
    "memcached"
    "mongodb"
    "mysql"
    "net"
    "netstat"
    "nginx"
    "postfix"
    "postgresql"
    "powerdns"
    "processes"
    "rabbitmq"
    "redis"
    "socket_listener"
    "swap"
    "system"
    "varnish"
    "conntrack"
    "psi"
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

  flyingcircus.roles.statshost.ldapMemberOf = "crew";
}
