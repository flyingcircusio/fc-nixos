{
  disabledModules = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
  ];

  imports = [
    ./box/client.nix
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
