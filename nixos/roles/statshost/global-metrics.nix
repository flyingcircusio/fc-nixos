{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  # Add metric prefixes here that should be accepted by the central statshost.
  # Replaces flyingcircus.statshost.globalAllowedMetrics in role code.
  # This also includes the host metrics from telegraf defined in platform/monitoring.nix.
  globalAllowedMetrics = [
    "apache"
    "ceph"
    "conntrack"
    "cpu"
    "disk"
    "diskio"
    "dnsdist"
    "elasticsearch"
    "fc_maintenance"
    "graylog"
    "haproxy"
    "jitsi"
    "kernel"
    "kubernetes"
    "mem"
    "memcached"
    "mongodb"
    "mysql"
    "neighbour"
    "net"
    "netstat"
    "nginx"
    "nstat"
    "pdns_auth"
    "postfix"
    "postgresql"
    "powerdns"
    "processes"
    "psi"
    "rabbitmq"
    "redis"
    "routes"
    "skvaider"
    "socket_listener"
    "swap"
    "system"
    "varnish"
  ];

  markAllowedMetrics = map (name: {
    source_labels = [ "__name__" ];
    regex = "${name}_.*";
    replacement = "yes";
    target_label = "__tmp_globally_allowed";
  }) config.flyingcircus.roles.statshost-global.allowedMetricPrefixes;

  dropUnmarkedMetrics = [
    {
      source_labels = [ "__tmp_globally_allowed" ];
      regex = "yes";
      action = "keep";
    }
    {
      regex = "__tmp_globally_allowed";
      action = "labeldrop";
    }
  ];

in
mkIf config.flyingcircus.roles.statshost-global.enable {
  # Telegraf host metrics are added in platform/monitoring.nix.
  flyingcircus.roles.statshost-global.allowedMetricPrefixes = globalAllowedMetrics;

  flyingcircus.roles.statshost.prometheusMetricRelabel = lib.mkAfter (
    markAllowedMetrics ++ dropUnmarkedMetrics
  );
}
