{
  disabledModules = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
  ];

  imports = [
    ./collectdproxy.nix
    ./haproxy.nix
    ./logrotate
    ./nginx
    ./prometheus.nix
    ./redis.nix
    ./sensu.nix
    ./syslog.nix
    ./telegraf.nix
  ];
}
