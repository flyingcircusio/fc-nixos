{ lib, ... }:
{
  disabledModules = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
  ];

  imports = with lib; [
    ./box/client.nix
    ./collectdproxy.nix
    ./graylog.nix
    ./haproxy.nix
    ./logrotate
    ./nginx
    ./percona.nix
    ./postgresql.nix
    ./prometheus.nix
    ./rabbitmq36.nix
    ./rabbitmq.nix
    ./redis.nix
    ./sensu.nix
    ./ssmtp.nix
    ./syslog.nix
    ./telegraf.nix

    (mkRemovedOptionModule [ "flyingcircus" "services" "percona" "rootPassword" ] "Change the root password via MySQL and modify secret files")
  ];
}
