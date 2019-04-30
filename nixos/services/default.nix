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
    ./postfix.nix
    ./prometheus.nix
    ./redis.nix
    ./sensu.nix
    ./ssmtp.nix
    ./syslog.nix
    ./telegraf.nix
  ];
}
