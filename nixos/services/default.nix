{ lib, ... }:
let
  modulesFromHere = [
    "services/monitoring/prometheus.nix"
    "services/monitoring/prometheus/default.nix"
    "services/web-apps/matomo.nix"
  ];

in
{
  disabledModules = modulesFromHere;

  imports = with lib; [
    ./ceph/client.nix
    ./ceph/server.nix
    ./consul
    ./ferretdb.nix
    ./graylog
    ./haproxy
    ./k3s/frontend.nix
    ./logrotate
    ./matomo
    ./nginx
    ./nullmailer.nix
    ./opensearch.nix
    ./opensearch_dashboards.nix
    ./percona.nix
    ./postgresql
    ./prometheus.nix
    ./rabbitmq
    ./rabbitmq/365frozen.nix
    ./raid
    ./redis.nix
    ./sensu/client.nix
    ./solr.nix
    ./telegraf
    ./varnish
    ./vinyl-cache
    ./wazuh

    (mkRemovedOptionModule [
      "flyingcircus"
      "services"
      "percona"
      "rootPassword"
    ] "Change the root password via MySQL and modify secret files")
  ];
}
