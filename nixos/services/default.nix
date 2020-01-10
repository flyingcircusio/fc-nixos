{
  disabledModules = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
  ];

  imports = [
    ./box/client.nix
    ./collectdproxy.nix
    ./graylog.nix
    ./haproxy.nix
    ./logrotate
    ./nginx
    ./percona.nix
    ./postfix.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq36.nix
    ./rabbitmq37.nix
    ./redis.nix
    ./sensu.nix
    ./ssmtp.nix
    ./syslog.nix
    ./telegraf.nix
  ];
}
