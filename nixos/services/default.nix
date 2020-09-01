{ lib, ... }:
let
  modulesFromHere = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
    "services/web-servers/nginx/default.nix"
  ];

  modulesFromUnstable = [
    "services/monitoring/grafana.nix"
    "services/search/elasticsearch.nix"
    "services/search/kibana.nix"
  ];

  nixpkgs-unstable-src = (import ../../versions.nix {}).nixos-unstable;

in {
  disabledModules = modulesFromUnstable ++ modulesFromHere;

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
  ] ++ map (m: "${nixpkgs-unstable-src}/nixos/modules/${m}") modulesFromUnstable;
}
